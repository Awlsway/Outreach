import 'dart:convert';
import 'package:ansvk_outreach/database/app_database.dart';
import 'package:ansvk_outreach/database/outreach_repository.dart';
import 'package:ansvk_outreach/sync/pairing_response.dart';
import 'package:ansvk_outreach/sync/sync_batch_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late AppDatabase db;
  late OutreachRepository repo;
  late DateTime now;
  String? owner;
  late String site;
  late Map<String, Object?> identity;
  setUp(() async {
    sqfliteFfiInit();
    db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    now = DateTime(2026, 9, 20, 23, 59);
    repo = OutreachRepository(
      db,
      currentWorkerId: () => owner,
      clock: () => now,
    );
    owner = await repo.createWorkerProfile('synthetic');
    site = await repo.createHotspot(name: 'Keep site', peers: ['Keep peer']);
    identity = await repo.appIdentity();
    await repo.saveDashboardPairing('https://127.0.0.1:3443/api/v1', '123456');
    await repo.applyDashboardPairing(
      PairingSuccess(
        requestId: 'test',
        dashboardId: 'dashboard',
        dashboardName: 'Test',
        deviceId: identity['device_id'] as String,
        workerId: owner!,
        deviceCredential: 'test',
        pairedAt: DateTime.utc(2026),
        serverTime: DateTime.utc(2026),
      ),
    );
  });
  tearDown(() async {
    owner = null;
    await db.close();
  });
  Future<String> create(String code) => repo.createEncounter({
    'hotspot_id': site,
    'client_code': code,
    'remark': 'Private $code',
  });
  Future<void> acknowledge({String destination = 'dashboard'}) async {
    for (final batch
        in SyncBatchBuilder(appVersion: 'test', clock: () => now).build(
          appIdentity: identity,
          workerId: owner!,
          pendingOperations: await repo.pendingOperations(),
        )) {
      final sent = jsonDecode(batch.jsonBody);
      await repo.applySyncAcknowledgement(
        sentBatch: batch,
        expectedDashboardId: destination,
        httpStatus: 200,
        response: {
          'ok': true,
          'request_id': 'test',
          'batch_id': sent['batch_id'],
          'dashboard_received_at': '2026-09-27T00:00:00Z',
          'warnings': [],
          'rejected': [],
          'retry_after_seconds': null,
          'accepted': [
            for (final op in sent['operations'])
              {
                for (final k in [
                  'operation_id',
                  'entity_type',
                  'entity_id',
                  'revision',
                  'sequence',
                ])
                  k: op[k],
                'accepted_at': '2026-09-27T00:00:00Z',
                'duplicate': false,
              },
          ],
        },
      );
    }
  }

  Future<dynamic> cleanup({bool Function()? mayContinue}) =>
      repo.cleanupAcknowledgedEncounters(
        expectedDashboardId: 'dashboard',
        expectedProjectId: identity['project_id'] as String,
        expectedDeviceId: identity['device_id'] as String,
        mayContinue: mayContinue,
      );

  test(
    'proof insertion failure and mismatched receipt destination cannot acknowledge operations',
    () async {
      await create('2026/MY/0001');
      await expectLater(acknowledge(destination: 'foreign'), throwsStateError);
      expect(await repo.pendingOperations(), hasLength(3));
      await db.connection.execute(
        "CREATE TRIGGER fail_proof BEFORE INSERT ON sync_confirmations BEGIN SELECT RAISE(ABORT,'synthetic'); END",
      );
      await expectLater(acknowledge(), throwsA(isA<DatabaseException>()));
      expect(await repo.pendingOperations(), hasLength(3));
      expect(await db.connection.query('sync_confirmations'), isEmpty);
      expect((await repo.syncStatus())['last_successful_sync_at'], isNull);
    },
  );
  test(
    'calendar cutoff crosses the year boundary without deleting the sixth prior day',
    () async {
      now = DateTime(2025, 12, 28);
      final old = await create('2026/MY/0001');
      now = DateTime(2025, 12, 29);
      final keep = await create('2026/MY/0002');
      await acknowledge();
      now = DateTime(2026, 1, 4);
      expect((await repo.syncStatus())['retention_cutoff_day'], '2025-12-29');
      expect((await cleanup()).removed, 1);
      expect(await repo.encounter(old), isNull);
      expect(await repo.encounter(keep), isNotNull);
    },
  );
  test(
    'calendar boundary removes old record and every payload, preserving sites and proof',
    () async {
      final old = await create('2026/MY/0001');
      now = DateTime(2026, 9, 21);
      final boundary = await create('2026/MY/0002');
      now = DateTime(2026, 9, 27);
      final today = await create('2026/MY/0003');
      await acknowledge();
      final proofs = await db.connection.query('sync_confirmations');
      final pending = await repo.pendingOperations();
      final result = await cleanup();
      expect(result.removed, 1);
      expect(result.held, 0);
      expect(await repo.encounter(old), isNull);
      expect(await repo.encounter(boundary), isNotNull);
      expect(await repo.encounter(today), isNotNull);
      expect(
        await db.connection.query(
          'audit_operations',
          where: 'entity_id=?',
          whereArgs: [old],
        ),
        isEmpty,
      );
      expect(
        await db.connection.rawQuery(
          "SELECT * FROM audit_operations WHERE payload LIKE '%2026/MY/0001%'",
        ),
        isEmpty,
      );
      expect(await db.connection.query('sync_confirmations'), proofs);
      expect(await repo.pendingOperations(), pending);
      expect((await repo.hotspots()).single['peers'], ['Keep peer']);
      final status = await repo.syncStatus();
      expect(status['retention_last_removed'], 1);
      expect(status['retention_checked_at'], isNotNull);
      expect(status['retention_cleanup_at'], isNotNull);
      expect((await cleanup()).removed, 0);
    },
  );
  test(
    'unsynced and newer edited records are held; deletion markers are removable after proof',
    () async {
      final edited = await create('2026/MY/0001');
      final deleted = await create('2026/MY/0002');
      await acknowledge();
      await repo.updateEncounter(edited, {
        'remark': 'newer',
      }, expectedRevision: 1);
      await repo.deleteEncounter(deleted, expectedRevision: 1);
      await acknowledge();
      await repo.updateEncounter(edited, {
        'remark': 'not yet accepted',
      }, expectedRevision: 2);
      await create('2026/MY/0003');
      now = DateTime(2026, 9, 27);
      final result = await cleanup();
      expect(result.removed, 1);
      expect(result.held, 2);
      expect(await repo.encounter(deleted), isNull);
      expect(
        await db.connection.query(
          'audit_operations',
          where: 'entity_id=?',
          whereArgs: [deleted],
        ),
        isEmpty,
      );
      expect(await repo.pendingOperations(), hasLength(2));
      expect((await repo.encounter(edited))!['remark'], 'not yet accepted');
    },
  );
  test(
    'missing outbox/audit/proof, wrong destination and state mismatch cannot authorize cleanup',
    () async {
      final missingOutbox = await create('2026/MY/0001');
      final missingAudit = await create('2026/MY/0002');
      final missingProof = await create('2026/MY/0003');
      final foreignProof = await create('2026/MY/0004');
      final modified = await create('2026/MY/0005');
      await acknowledge();
      await db.connection.rawDelete(
        'DELETE FROM sync_outbox WHERE operation_id IN (SELECT operation_id FROM audit_operations WHERE entity_id IN (?,?))',
        [missingOutbox, missingAudit],
      );
      await db.connection.delete(
        'audit_operations',
        where: 'entity_id=?',
        whereArgs: [missingAudit],
      );
      await db.connection.delete(
        'sync_confirmations',
        where: 'entity_id=?',
        whereArgs: [missingProof],
      );
      await db.connection.update(
        'sync_confirmations',
        {'dashboard_id': 'foreign'},
        where: 'entity_id=?',
        whereArgs: [foreignProof],
      );
      await db.connection.update(
        'encounters',
        {'remark': 'unproven state'},
        where: 'encounter_id=?',
        whereArgs: [modified],
      );
      now = DateTime(2026, 9, 27);
      expect(
        (await repo.syncStatus())['old_client_records_eligible_after_ack'],
        0,
      );
      final result = await cleanup();
      expect(result.removed, 0);
      expect(result.held, 5);
    },
  );
  test(
    'foreign worker data is retained and changed destination/session blocks cleanup',
    () async {
      final first = owner!;
      await create('2026/MY/0001');
      await acknowledge();
      owner = await repo.createWorkerProfile('other');
      site = await repo.createHotspot(name: 'Foreign');
      final foreign = await create('2026/MY/0002');
      await acknowledge();
      owner = first;
      now = DateTime(2026, 9, 27);
      await cleanup();
      expect(
        await db.connection.query(
          'encounters',
          where: 'encounter_id=?',
          whereArgs: [foreign],
        ),
        hasLength(1),
      );
      await db.connection.update('dashboard_connection', {
        'dashboard_id': 'different',
      });
      await expectLater(cleanup(), throwsStateError);
      owner = null;
      await expectLater(cleanup(), throwsStateError);
    },
  );
  test(
    'transaction failure or Stop rolls back payload removal and retention timestamps',
    () async {
      final old = await create('2026/MY/0001');
      await acknowledge();
      now = DateTime(2026, 9, 27);
      final audit = await db.connection.query('audit_operations');
      final outbox = await db.connection.query('sync_outbox');
      await db.connection.execute(
        "CREATE TRIGGER fail_cleanup BEFORE DELETE ON audit_operations BEGIN SELECT RAISE(ABORT,'test rollback'); END",
      );
      await expectLater(cleanup(), throwsA(isA<DatabaseException>()));
      expect(await db.connection.query('audit_operations'), audit);
      expect(await db.connection.query('sync_outbox'), outbox);
      expect(await repo.encounter(old), isNotNull);
      expect((await repo.syncStatus())['retention_checked_at'], isNull);
      await db.connection.execute('DROP TRIGGER fail_cleanup');
      var checks = 0;
      await expectLater(
        cleanup(mayContinue: () => ++checks < 3),
        throwsStateError,
      );
      expect(await db.connection.query('audit_operations'), audit);
      expect(await db.connection.query('sync_outbox'), outbox);
      expect((await repo.syncStatus())['retention_checked_at'], isNull);
    },
  );
}
