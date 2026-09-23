import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ansvk_outreach/database/app_database.dart';
import 'package:ansvk_outreach/database/outreach_repository.dart';
import 'package:ansvk_outreach/sync/certificate_fingerprint_store.dart';
import 'package:ansvk_outreach/sync/configured_manual_sync.dart';
import 'package:ansvk_outreach/sync/dashboard_pairing_service.dart';
import 'package:ansvk_outreach/sync/device_credential_store.dart';
import 'package:ansvk_outreach/sync/manual_sync_runner.dart';
import 'package:ansvk_outreach/sync/pairing_request_builder.dart';
import 'package:ansvk_outreach/sync/secure_sync_transport.dart';
import 'package:ansvk_outreach/sync/sync_batch_builder.dart';
import 'package:ansvk_outreach/sync/sync_status_response.dart';
import 'package:ansvk_outreach/sync/reviewed_sync_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  for (final restricted in [false, true]) {
    test(
      'APK actual LAN integration (restricted: $restricted)',
      () async {
        final lanRoot =
            Platform.environment['OUTREACH_LAN_TEST_ROOT'] ?? r'D:\LAN';
        final temp = await Directory.systemTemp.createTemp(
          'outreach-dart-lan-',
        );
        addTearDown(() => temp.delete(recursive: true));
        final openssl = Platform.isWindows
            ? r'C:\Program Files\Git\usr\bin\openssl.exe'
            : 'openssl';
        final cert = '${temp.path}/cert.pem';
        final key = '${temp.path}/key.pem';
        final generated = await Process.run(openssl, [
          'req',
          '-x509',
          '-newkey',
          'rsa:2048',
          '-nodes',
          '-keyout',
          key,
          '-out',
          cert,
          '-days',
          '1',
          '-subj',
          '/CN=synthetic-loopback',
          '-addext',
          'subjectAltName=IP:127.0.0.1',
        ]);
        expect(
          generated.exitCode,
          0,
          reason: 'Temporary test certificate generation',
        );
        sqfliteFfiInit();
        final db = await AppDatabase.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
        addTearDown(db.close);
        String? worker;
        final repo = OutreachRepository(db, currentWorkerId: () => worker);
        worker = await repo.createWorkerProfile('synthetic.dart.worker');
        final hotspot = await repo.createHotspot(
          name: 'Synthetic Dart Hotspot',
        );
        final encounter = await repo.createEncounter({
          'hotspot_id': hotspot,
          'client_code': '2026/MY/0001',
        });
        final identity = await repo.appIdentity();
        final approvalFile = File('${temp.path}/approval.json');
        if (restricted) {
          await approvalFile.writeAsString(
            jsonEncode({
              'version': 1,
              'sourceIp': '127.0.0.1',
              'expiresAt': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 2))
                  .toIso8601String(),
              'identity': {
                'projectId': identity['project_id'],
                'workerId': worker,
                'deviceId': identity['device_id'],
                'deviceCreatedAt': identity['created_at'],
              },
              'batch': null,
            }),
          );
        }
        final bridge = await Process.start('node', [
          '--import',
          'tsx',
          File('tools/synthetic_upload/dart_bridge.mts').absolute.path,
          cert,
          key,
          if (restricted) approvalFile.path,
        ], workingDirectory: lanRoot);
        final errors = <String>[];
        final errorDone = bridge.stderr
            .transform(utf8.decoder)
            .listen(errors.add);
        final replyQueue = StreamController<Map<String, dynamic>>();
        final outputDone = bridge.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .where((line) => line.startsWith('OUTREACH_BRIDGE '))
            .map(
              (line) =>
                  jsonDecode(line.substring('OUTREACH_BRIDGE '.length))
                      as Map<String, dynamic>,
            )
            .listen(replyQueue.add, onDone: replyQueue.close);
        final replies = StreamIterator(replyQueue.stream);
        var bridgeStopped = false;
        addTearDown(() async {
          if (!bridgeStopped) {
            try {
              bridge.stdin.writeln('{"action":"stop"}');
              await bridge.stdin.flush();
              await bridge.exitCode.timeout(const Duration(seconds: 10));
            } catch (_) {
              bridge.kill();
            }
          }
          await replies.cancel();
          await outputDone.cancel();
          await errorDone.cancel();
        });
        Future<Map<String, dynamic>> next() async {
          if (!await replies.moveNext().timeout(const Duration(seconds: 30))) {
            throw StateError('Loopback bridge closed unexpectedly');
          }
          return replies.current;
        }

        final ready = await next();
        final browser = HttpClient()..findProxy = (_) => 'DIRECT';
        addTearDown(() => browser.close(force: true));
        Future<({int status, Map<String, dynamic> json, String? cookie})> post(
          String path,
          Map<String, Object?> data, [
          String? cookie,
        ]) async {
          final request = await browser.postUrl(
            Uri.parse('${ready['browserUrl']}$path'),
          );
          request.headers.contentType = ContentType.json;
          if (cookie != null) {
            request.headers.set(HttpHeaders.cookieHeader, cookie);
          }
          request.write(jsonEncode(data));
          final reply = await request.close();
          final setCookie = reply.headers
              .value(HttpHeaders.setCookieHeader)
              ?.split(';')
              .first;
          return (
            status: reply.statusCode,
            json:
                jsonDecode(await utf8.decoder.bind(reply).join())
                    as Map<String, dynamic>,
            cookie: setCookie,
          );
        }

        final setup = await post('/api/setup-first-admin', {
          'username': 'synthetic.dart.admin@example.org',
          'name': 'Synthetic Dart Admin',
          'password':
              'Synthetic-${DateTime.now().microsecondsSinceEpoch}-Only!',
        });
        expect(setup.status, 200);
        final issued = await post(
          '/api/outreach/pairing-codes',
          {},
          setup.cookie,
        );
        expect(issued.status, 201);
        final code = issued.json['pairing']['pairing_code'] as String;
        final credentials = DeviceCredentialStore.memory();
        final pins = CertificateFingerprintStore();
        await pins.write(ready['fingerprint'] as String);
        final base = '${ready['deviceUrl']}/api/v1';
        await repo.saveDashboardPairing(base, code);
        final paired = await DashboardPairingService(
          repository: repo,
          credentialStore: credentials,
          requestBuilder: PairingRequestBuilder(
            appVersion: '0.9.8+23',
            clock: DateTime.now,
          ),
        ).pair(expectedCertificateFingerprint: ready['fingerprint'] as String);
        expect(paired.paired, isTrue);
        final builder = SyncBatchBuilder(
          appVersion: '0.9.8+23',
          clock: DateTime.now,
        );
        final statusTransport = SecureSyncTransport(
          baseUri: Uri.parse(base),
          fingerprint: ready['fingerprint'] as String,
          credentialStore: credentials,
        );
        final statusReply = await statusTransport.checkStatus();
        SyncStatusResponse.parse(
          statusReply.response,
          httpStatus: statusReply.httpStatus,
          expectedDeviceId: (await repo.appIdentity())['device_id'] as String,
          expectedWorkerId: worker,
        );
        final initial = await repo.pendingOperations();
        final reviewed = await ReviewedSyncPlan.prepare(repo, builder);
        final replayBatch = reviewed.batches.first;
        if (restricted) {
          expect((await statusTransport.send(replayBatch)).httpStatus, 403);
          expect(await repo.pendingOperations(), initial);
          bridge.stdin.writeln(
            jsonEncode({'action': 'approve', 'body': replayBatch.jsonBody}),
          );
          expect((await next())['approved'], isTrue);
          expect(
            (await statusTransport.send(
              PreparedSyncBatch('${replayBatch.jsonBody} '),
            )).httpStatus,
            403,
          );
        }
        final service = ConfiguredManualSync(
          repository: repo,
          fingerprintStore: pins,
          credentialStore: credentials,
          builder: builder,
          maxBatchesPerRun: 1,
        );
        final first = await service.run(reviewedPlan: reviewed);
        expect(first.outcome, ManualSyncOutcome.uploaded);
        expect(first.markedOperations, 3);
        expect(await repo.pendingOperations(), isEmpty);
        final replay = await SecureSyncTransport(
          baseUri: Uri.parse(base),
          fingerprint: ready['fingerprint'] as String,
          credentialStore: credentials,
        ).send(replayBatch);
        expect(replay.httpStatus, 200);
        expect(
          (replay.response['accepted'] as List).every(
            (op) => op['duplicate'] == true,
          ),
          isTrue,
        );
        expect(
          await repo.applySyncAcknowledgement(
            sentBatch: replayBatch,
            response: replay.response,
            httpStatus: replay.httpStatus,
          ),
          0,
        );
        await repo.updateEncounter(encounter, {
          'remark': 'Synthetic revision',
        }, expectedRevision: 1);
        await repo.deleteEncounter(encounter, expectedRevision: 2);
        final revisions = await repo.pendingOperations();
        final revisionStatus = await statusTransport.checkStatus();
        SyncStatusResponse.parse(
          revisionStatus.response,
          httpStatus: revisionStatus.httpStatus,
          expectedDeviceId: (await repo.appIdentity())['device_id'] as String,
          expectedWorkerId: worker,
        );
        final revisionReview = await ReviewedSyncPlan.prepare(repo, builder);
        final second = await service.run(reviewedPlan: revisionReview);
        expect(
          second.outcome,
          restricted ? ManualSyncOutcome.stopped : ManualSyncOutcome.uploaded,
        );
        expect(second.markedOperations, restricted ? 0 : 2);
        expect(
          await repo.pendingOperations(),
          restricted ? revisions : isEmpty,
        );
        if (!restricted) {
          expect((await service.run()).outcome, ManualSyncOutcome.emptyQueue);
        }
        bridge.stdin.writeln(
          jsonEncode({
            'action': 'inspect',
            'expected': [
              for (final op in [...initial, if (!restricted) ...revisions])
                {...op, 'payload': jsonDecode(op['payload'] as String)},
            ],
          }),
        );
        final inspected = await next();
        expect(inspected['matching'], isTrue);
        expect(inspected['operationCount'], restricted ? 3 : 5);
        expect(inspected['verifiedBackup'], isTrue);
        expect((await repo.syncStatus())['last_successful_sync_at'], isNull);
        bridge.stdin.writeln('{"action":"stop"}');
        expect((await next())['stopped'], isTrue);
        await bridge.stdin.close();
        expect(await bridge.exitCode.timeout(const Duration(seconds: 10)), 0);
        bridgeStopped = true;
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
