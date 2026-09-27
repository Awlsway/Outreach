import 'dart:io';
import 'package:ansvk_outreach/sync/sync_run_control.dart';
import 'dart:convert';
import 'package:ansvk_outreach/database/app_database.dart';
import 'package:ansvk_outreach/database/outreach_repository.dart';
import 'package:ansvk_outreach/sync/certificate_fingerprint_store.dart';
import 'package:ansvk_outreach/sync/configured_manual_sync.dart';
import 'package:ansvk_outreach/sync/dashboard_certificate_checker.dart';
import 'package:ansvk_outreach/sync/device_credential_store.dart';
import 'package:ansvk_outreach/sync/manual_sync_runner.dart';
import 'package:ansvk_outreach/sync/pairing_response.dart';
import 'package:ansvk_outreach/sync/secure_sync_transport.dart';
import 'package:ansvk_outreach/sync/sync_batch_builder.dart';
import 'package:ansvk_outreach/sync/reviewed_sync_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TestConnection implements SyncHttpsConnection {
  TestConnection(this.respond);
  final Future<SyncBatchReply> Function(Uri, String?) respond;
  @override
  List<int> get certificateDer => [1, 2, 3];
  @override
  Future<SyncBatchReply> request(
    Uri uri,
    String method,
    String credential,
    String? body,
  ) => respond(uri, body);
  @override
  void close() {}
}

void main() {
  late AppDatabase db;
  late OutreachRepository repo;
  late ConfiguredManualSync service;
  late CertificateFingerprintStore pins;
  late DeviceCredentialStore credentials;
  late Map<String, Object?> identity;
  String? worker;
  late List<String> paths;
  late List<String> uploadBodies;
  late String statusDevice;
  late String deviceStatus;
  Future<void> Function()? duringUpload;
  Future<void> Function()? duringConnect;
  setUp(() async {
    sqfliteFfiInit();
    db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repo = OutreachRepository(db, currentWorkerId: () => worker);
    worker = await repo.createWorkerProfile('synthetic');
    await repo.createHotspot(name: 'Synthetic');
    identity = await repo.appIdentity();
    statusDevice = identity['device_id'] as String;
    deviceStatus = 'active';
    pins = CertificateFingerprintStore();
    await pins.write(await DashboardCertificateChecker.sha256Hex([1, 2, 3]));
    credentials = DeviceCredentialStore.memory();
    await credentials.write('synthetic-credential');
    await repo.saveDashboardPairing('https://127.0.0.1:3443/api/v1', '123456');
    await repo.applyDashboardPairing(
      PairingSuccess(
        requestId: 'synthetic',
        dashboardId: 'dashboard',
        dashboardName: 'Synthetic',
        deviceId: statusDevice,
        workerId: worker!,
        deviceCredential: 'synthetic',
        pairedAt: DateTime.utc(2026),
        serverTime: DateTime.utc(2026),
      ),
    );
    paths = [];
    uploadBodies = [];
    duringUpload = null;
    duringConnect = null;
    service = ConfiguredManualSync(
      repository: repo,
      fingerprintStore: pins,
      credentialStore: credentials,
      retryWait: (_) async {},
      retryRandom: () => .5,
      builder: SyncBatchBuilder(
        appVersion: 'test',
        clock: () => DateTime.utc(2026),
      ),
      connector: (_) async {
        await duringConnect?.call();
        return TestConnection((uri, body) async {
          paths.add(uri.path);
          if (body == null) {
            return SyncBatchReply(200, {
              'ok': true,
              'request_id': 'synthetic',
              'device_id': statusDevice,
              'worker_id': worker,
              'device_status': deviceStatus,
              'cleanup_keep_days': 7,
              'server_time': '2026-09-17T00:00:00Z',
              'warnings': [],
              'last_successful_sync_at': null,
              'last_accepted_sequence': null,
              'last_accepted_operation_id': null,
            });
          }
          uploadBodies.add(body);
          final request = jsonDecode(body);
          await duringUpload?.call();
          return SyncBatchReply(200, {
            'ok': true,
            'request_id': 'synthetic',
            'batch_id': request['batch_id'],
            'dashboard_received_at': '2026-09-17T00:00:00Z',
            'warnings': [],
            'retry_after_seconds': null,
            'rejected': [],
            'accepted': [
              for (final op in request['operations'])
                {
                  for (final key in [
                    'operation_id',
                    'entity_type',
                    'entity_id',
                    'revision',
                    'sequence',
                  ])
                    key: op[key],
                  'duplicate': false,
                  'accepted_at': '2026-09-17T00:00:00Z',
                },
            ],
          });
        });
      },
    );
  });
  test(
    'normal run retries identical bytes after lost receipt and acknowledges once',
    () async {
      var attempts = 0;
      duringUpload = () async {
        if (++attempts == 1) throw const SocketException('lost receipt');
      };
      final result = await service.run(control: SyncRunControl());
      expect(result.outcome, ManualSyncOutcome.uploaded);
      expect(result.markedOperations, 2);
      expect(uploadBodies, hasLength(2));
      expect(uploadBodies[0], uploadBodies[1]);
      expect(await repo.pendingOperations(), isEmpty);
    },
  );
  test(
    'Stop during upload leaves all unconfirmed operations pending',
    () async {
      final control = SyncRunControl();
      duringUpload = () async {
        control.stop();
      };
      final result = await service.run(control: control);
      expect(result.outcome, ManualSyncOutcome.stopped);
      expect(result.markedOperations, 0);
      expect(await repo.pendingOperations(), hasLength(2));
      expect((await repo.syncStatus())['last_successful_sync_at'], isNull);
    },
  );
  test(
    'authenticated empty queue cleans aged confirmed data without sending or inventing a sync time',
    () async {
      var now = DateTime(2026, 9, 20);
      repo = OutreachRepository(
        db,
        currentWorkerId: () => worker,
        clock: () => now,
      );
      final site = (await repo.hotspots()).single['hotspot_id'];
      final old = await repo.createEncounter({
        'hotspot_id': site,
        'client_code': '2026/MY/0070',
      });
      final run = ConfiguredManualSync(
        repository: repo,
        fingerprintStore: pins,
        credentialStore: credentials,
        builder: service.builder,
        connector: service.connector,
      );
      expect((await run.run()).outcome, ManualSyncOutcome.uploaded);
      expect(await repo.encounter(old), isNotNull);
      final time = (await repo.syncStatus())['last_successful_sync_at'];
      final sends = uploadBodies.length;
      now = DateTime(2026, 9, 27);
      final result = await run.run();
      expect(result.outcome, ManualSyncOutcome.emptyQueue);
      expect(result.cleanup!.removed, 1);
      expect(uploadBodies.length, sends);
      expect(await repo.encounter(old), isNull);
      expect((await repo.syncStatus())['last_successful_sync_at'], time);
    },
  );
  test(
    'cleanup failure preserves confirmed upload and completion time',
    () async {
      await db.connection.execute(
        "CREATE TRIGGER fail_retention BEFORE UPDATE ON sync_state WHEN NEW.retention_checked_at IS NOT NULL BEGIN SELECT RAISE(ABORT,'synthetic'); END",
      );
      final result = await service.run();
      expect(result.outcome, ManualSyncOutcome.uploaded);
      expect(result.markedOperations, 2);
      expect(result.cleanupFailed, isTrue);
      expect(await repo.pendingOperations(), isEmpty);
      expect((await repo.syncStatus())['last_successful_sync_at'], isNotNull);
      expect((await repo.syncStatus())['retention_checked_at'], isNull);
    },
  );
  tearDown(() async {
    await db.close();
    worker = null;
  });
  test(
    'checks authenticated status before uploads and for empty queue',
    () async {
      expect((await service.run()).outcome, ManualSyncOutcome.uploaded);
      expect(paths, ['/api/v1/sync/status', '/api/v1/sync/batches']);
      expect(await repo.pendingOperations(), isEmpty);
      expect((await service.run()).outcome, ManualSyncOutcome.emptyQueue);
      expect(paths.last, '/api/v1/sync/status');
      expect(
        (await repo.syncStatus())['last_successful_sync_at'],
        '2026-09-17T00:00:00.000Z',
      );
    },
  );
  test('foreign status blocks upload and leaves queue intact', () async {
    statusDevice = 'foreign';
    expect((await service.run()).outcome, ManualSyncOutcome.stopped);
    expect(paths, ['/api/v1/sync/status']);
    expect(await repo.pendingOperations(), hasLength(2));
  });
  for (final state in ['revoked', 'retired']) {
    test(
      'ordinary Sync refuses $state device without upload or cleanup',
      () async {
        deviceStatus = state;
        final result = await service.run(control: SyncRunControl());
        expect(result.outcome, ManualSyncOutcome.stopped);
        expect(paths, ['/api/v1/sync/status']);
        expect(uploadBodies, isEmpty);
        expect(await repo.pendingOperations(), hasLength(2));
        final status = await repo.syncStatus();
        expect(status['last_successful_sync_at'], isNull);
        expect(status['retention_checked_at'], isNull);
      },
    );
  }
  test(
    'reviewed run sends exact frozen bytes and cannot reuse consumed review',
    () async {
      final plan = await ReviewedSyncPlan.prepare(repo, service.builder);
      final originalBody = plan.batches.first.jsonBody;
      expect(
        (await service.run(reviewedPlan: plan)).outcome,
        ManualSyncOutcome.uploaded,
      );
      expect(uploadBodies, [originalBody]);
      expect(
        (await service.run(reviewedPlan: plan)).outcome,
        ManualSyncOutcome.stopped,
      );
      expect(uploadBodies, hasLength(1));
      expect(() => plan.batches.clear(), throwsUnsupportedError);
    },
  );
  test(
    'new operation after review blocks requests and preserves pending queue',
    () async {
      final plan = await ReviewedSyncPlan.prepare(repo, service.builder);
      await repo.createHotspot(name: 'Added after review');
      expect(
        (await service.run(reviewedPlan: plan)).outcome,
        ManualSyncOutcome.stopped,
      );
      expect(paths, isEmpty);
      expect(await repo.pendingOperations(), hasLength(3));
    },
  );
  test('change during status invalidates review before upload', () async {
    final plan = await ReviewedSyncPlan.prepare(repo, service.builder);
    var connected = false;
    duringConnect = () async {
      if (!connected) {
        connected = true;
        await repo.createHotspot(name: 'Changed during connection');
      }
    };
    expect(
      (await service.run(reviewedPlan: plan)).outcome,
      ManualSyncOutcome.stopped,
    );
    expect(uploadBodies, isEmpty);
    expect(await repo.pendingOperations(), hasLength(3));
  });
  test('configured service enforces first-test one-batch bound', () async {
    for (var i = 0; i < 99; i++) {
      await repo.createHotspot(name: 'Additional synthetic $i');
    }
    service = ConfiguredManualSync(
      repository: repo,
      fingerprintStore: pins,
      credentialStore: credentials,
      builder: service.builder,
      connector: service.connector,
      maxBatchesPerRun: 1,
    );
    final result = await service.run();
    expect(result.outcome, ManualSyncOutcome.batchLimitReached);
    expect(result.markedOperations, 100);
    expect(paths, ['/api/v1/sync/status', '/api/v1/sync/batches']);
    expect(await repo.pendingOperations(), hasLength(1));
  });
  test('unpaired or missing credential blocks all HTTP requests', () async {
    await credentials.clear();
    expect((await service.run()).outcome, ManualSyncOutcome.stopped);
    await credentials.write('synthetic-credential');
    await repo.clearDashboardAddress();
    expect((await service.run()).outcome, ManualSyncOutcome.stopped);
    expect(paths, isEmpty);
  });
  test(
    'context changed during TLS setup prevents HTTP secrets being sent',
    () async {
      duringConnect = pins.clear;
      expect((await service.run()).outcome, ManualSyncOutcome.stopped);
      expect(paths, isEmpty);
      expect(await repo.pendingOperations(), hasLength(2));
    },
  );
  test(
    'cleared pairing or lock during upload cannot apply acknowledgement',
    () async {
      duringUpload = repo.clearDashboardAddress;
      expect((await service.run()).outcome, ManualSyncOutcome.stopped);
      expect(await repo.pendingOperations(), hasLength(2));
    },
  );
  test('worker lock during upload cannot apply acknowledgement', () async {
    duringUpload = () async {
      worker = null;
    };
    expect((await service.run()).outcome, ManualSyncOutcome.stopped);
    expect(
      (await db.connection.query(
        'sync_outbox',
      )).every((r) => r['acknowledged_at'] == null),
      isTrue,
    );
  });
}
