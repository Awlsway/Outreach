import 'dart:convert';
import 'dart:io';
import 'package:ansvk_outreach/database/app_database.dart';
import 'package:ansvk_outreach/database/schema.dart';
import 'package:ansvk_outreach/database/outreach_repository.dart';
import 'package:ansvk_outreach/sync/pairing_request_builder.dart';
import 'package:ansvk_outreach/sync/sync_batch_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'storage 6 to 7 preserves legacy operations and reconfirms without changing wire schema6',
    () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp(
        'outreach-retention-migration-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/test.db';
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 6,
          onCreate: (db, version) => migrate(db, 0, version),
          onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
        ),
      );
      const stamp = '2026-09-20T00:00:00Z';
      await legacy.insert('workers', {
        'worker_id': 'worker',
        'username': 'legacy',
        'created_at': stamp,
      });
      await legacy.insert('sync_state', {
        'worker_id': 'worker',
        'last_successful_sync_at': stamp,
      });
      await legacy.insert('hotspots', {
        'hotspot_id': 'site',
        'owner_id': 'worker',
        'name': 'Keep',
        'created_at': stamp,
      });
      await legacy.insert('encounters', {
        'encounter_id': 'encounter',
        'owner_id': 'worker',
        'hotspot_id': 'site',
        'client_code': '2026/MY/0001',
        'visit_date': '2026-09-20',
        'created_at': stamp,
        'updated_at': stamp,
      });
      final payload = jsonEncode((await legacy.query('encounters')).single);
      await legacy.insert('audit_operations', {
        'operation_id': 'operation',
        'actor_id': 'worker',
        'entity_type': 'encounter',
        'entity_id': 'encounter',
        'revision': 1,
        'action': 'create',
        'occurred_at': stamp,
        'payload': payload,
      });
      await legacy.insert('sync_outbox', {
        'operation_id': 'operation',
        'acknowledged_at': stamp,
      });
      final original = (await legacy.query('audit_operations')).single;
      await legacy.close();
      final db = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      addTearDown(db.close);
      expect(await db.connection.getVersion(), 7);
      expect((await db.connection.query('audit_operations')).single, original);
      expect(
        (await db.connection.query('sync_outbox')).single['acknowledged_at'],
        isNull,
      );
      expect(await db.connection.query('sync_confirmations'), isEmpty);
      final repo = OutreachRepository(db, currentWorkerId: () => 'worker');
      final identity = await repo.appIdentity();
      final worker = await repo.currentWorkerProfile();
      final pairing = PairingRequestBuilder(
        appVersion: 'test',
        clock: () => DateTime.utc(2026),
      ).build(appIdentity: identity, worker: worker, pairingCode: '123456');
      final batch =
          SyncBatchBuilder(appVersion: 'test', clock: () => DateTime.utc(2026))
              .build(
                appIdentity: identity,
                workerId: 'worker',
                pendingOperations: await repo.pendingOperations(),
              )
              .single;
      expect(pairing['schema_version'], 6);
      expect(jsonDecode(batch.jsonBody)['schema_version'], 6);
      expect(
        jsonDecode(batch.jsonBody)['operations'].single['operation_id'],
        'operation',
      );
      expect(
        (await db.connection.query('encounters')).single['client_code'],
        '2026/MY/0001',
      );
    },
  );
}
