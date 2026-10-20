import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ansvk_outreach/database/app_database.dart';
import 'package:ansvk_outreach/database/outreach_repository.dart';
import 'package:ansvk_outreach/sync/certificate_fingerprint_store.dart';
import 'package:ansvk_outreach/sync/device_credential_store.dart';
import 'package:ansvk_outreach/sync/initial_certificate_trust.dart';
import 'package:ansvk_outreach/sync/qr_pairing_coordinator.dart';
import 'package:ansvk_outreach/sync/dashboard_pairing_service.dart';
import 'package:ansvk_outreach/sync/secure_sync_transport.dart';
import 'package:ansvk_outreach/sync/configured_manual_sync.dart';
import 'package:ansvk_outreach/sync/sync_batch_builder.dart';
import 'package:ansvk_outreach/sync/manual_sync_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'jvm_certificate_test_support.dart';

void main() {
  test(
    'real LAN paired credential bootstraps and confirms exact persisted trust',
    () async {
      final metadata = await JvmCertificateReader.create();
      metadata.install();
      addTearDown(metadata.close);
      final temp = await Directory.systemTemp.createTemp(
        'outreach-initial-lan-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final cert = '${temp.path}/cert.pem', key = '${temp.path}/key.pem';
      final result =
          await Process.run(r'C:\Program Files\Git\usr\bin\openssl.exe', [
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
            '/CN=synthetic',
            '-addext',
            'subjectAltName=IP:127.0.0.1',
          ]);
      expect(result.exitCode, 0);
      final bridge = await Process.start('node', [
        '--import',
        'tsx',
        r'D:\LAN\tools\initial_trust_uat\dart_bridge.mts',
        cert,
        key,
      ], workingDirectory: r'D:\LAN');
      final queue = StreamController<Map<String, dynamic>>();
      final errors = <String>[];
      final stderr = bridge.stderr.transform(utf8.decoder).listen(errors.add);
      final stdout = bridge.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.startsWith('OUTREACH_TRUST_BRIDGE ')) {
              queue.add(
                jsonDecode(line.substring('OUTREACH_TRUST_BRIDGE '.length)),
              );
            }
          }, onDone: queue.close);
      final output = StreamIterator(queue.stream);
      addTearDown(() async {
        bridge.stdin.writeln('{"action":"stop"}');
        await bridge.stdin.flush();
        await bridge.stdin.close();
        await bridge.exitCode.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            bridge.kill();
            return -1;
          },
        );
        await stdout.cancel();
        await stderr.cancel();
        await output.cancel();
      });
      Future<Map<String, dynamic>> next() async {
        expect(
          await output.moveNext().timeout(const Duration(seconds: 20)),
          true,
          reason: errors.join(),
        );
        return output.current;
      }

      final started = await next();
      sqfliteFfiInit();
      final db = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: '${temp.path}/phone.db',
      );
      addTearDown(db.close);
      String? worker;
      final repo = OutreachRepository(db, currentWorkerId: () => worker);
      worker = await repo.createWorkerProfile('synthetic.trust.worker');
      await repo.createHotspot(name: 'kept');
      final pins = CertificateFingerprintStore(),
          credentials = DeviceCredentialStore.memory();
      final paired = await QrPairingCoordinator(
        repository: repo,
        certificateFingerprintStore: pins,
        deviceCredentialStore: credentials,
        appVersion: '0.9.10+25',
      ).pairFromQr(started['pairing']['qr_text']);
      expect(paired.status, DashboardPairingAttemptStatus.paired);
      final credential = await credentials.read(),
          identity = await repo.appIdentity(),
          pending = await repo.pendingOperations();
      final trust = InitialCertificateTrust(
        repository: repo,
        legacyPins: pins,
        credentials: credentials,
      );
      final before = await SecureSyncTransport(
        baseUri: Uri.parse(started['api_base_url']),
        fingerprint: started['certificate_sha256'],
        credentialStore: credentials,
      ).checkStatus();
      expect(before.httpStatus, 409);
      expect(before.response['error_code'], 'certificate_trust_required');
      await trust.ensure();
      final pin = await trust.confirmedPin();
      expect(pin, hasLength(64));
      expect(await pins.read(), null);
      expect(await credentials.read(), credential);
      expect(await repo.appIdentity(), identity);
      expect(await repo.pendingOperations(), pending);
      await trust.ensure(); // idempotent local resume, no re-enrollment
      bridge.stdin.writeln('{"action":"status"}');
      await bridge.stdin.flush();
      final readiness = (await next())['readiness'] as Map;
      expect(readiness['ready'], true);
      expect(readiness['generation'], 1);
      final rows = readiness['devices'] as List;
      expect(rows, hasLength(1));
      expect(rows.single['device_id'], identity['device_id']);
      expect(rows.single['worker_id'], worker);
      expect(rows.single['state'], 'ready');
      expect(rows.single['confirmed_at'], isNotNull);
      final uploaded = await ConfiguredManualSync(
        repository: repo,
        fingerprintStore: pins,
        credentialStore: credentials,
        builder: SyncBatchBuilder(appVersion: '0.9.10+25', clock: DateTime.now),
      ).run();
      expect(uploaded.outcome, ManualSyncOutcome.uploaded);
      expect(uploaded.markedOperations, 2);
      expect(await repo.pendingOperations(), isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
