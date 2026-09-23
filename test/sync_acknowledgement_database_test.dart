import 'dart:convert';

import 'package:ansvk_outreach/database/app_database.dart';
import 'package:ansvk_outreach/database/outreach_repository.dart';
import 'package:ansvk_outreach/sync/sync_batch_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late AppDatabase db;
  late OutreachRepository repo;
  String? owner;
  late String encounter;
  late PreparedSyncBatch batch;
  late Map<String, dynamic> response;
  setUp(() async {
    sqfliteFfiInit();
    db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repo = OutreachRepository(db, currentWorkerId: () => owner);
    owner = await repo.createWorkerProfile('synthetic');
    final hotspot = await repo.createHotspot(name: 'Synthetic');
    encounter = await repo.createEncounter({
      'hotspot_id': hotspot,
      'client_code': '2026/MY/0001',
    });
    batch =
        SyncBatchBuilder(appVersion: 'test', clock: () => DateTime.utc(2026))
            .build(
              appIdentity: await repo.appIdentity(),
              workerId: owner!,
              pendingOperations: await repo.pendingOperations(),
            )
            .single;
    final sent = jsonDecode(batch.jsonBody) as Map<String, dynamic>;
    response = {
      'ok': true,
      'batch_id': sent['batch_id'],
      'request_id': 'synthetic-request',
      'dashboard_received_at': '2026-09-17T00:00:00Z',
      'accepted': [
        for (final op in sent['operations'])
          {
            for (final key in [
              'operation_id',
              'entity_type',
              'entity_id',
              'revision',
              'sequence',
            ])
              key: op[key],
            'accepted_at': '2026-09-17T00:00:00Z',
            'duplicate': false,
          },
      ],
      'rejected': [],
      'warnings': [],
      'retry_after_seconds': null,
    };
  });
  tearDown(() async {
    await db.close();
    owner = null;
  });
  Future<int> apply() => repo.applySyncAcknowledgement(
    sentBatch: batch,
    response: response,
    httpStatus: 200,
  );

  test(
    'exact acceptance preserves audit and newer edit; repeat is idempotent',
    () async {
      await repo.updateEncounter(encounter, {
        'remark': 'newer',
      }, expectedRevision: 1);
      final audit = await db.connection.query('audit_operations');
      final records = await db.connection.query('encounters');
      expect(await apply(), 3);
      final pending = await repo.pendingOperations();
      expect(pending, hasLength(1));
      expect(pending.single['revision'], 2);
      expect(await db.connection.query('audit_operations'), audit);
      expect(await db.connection.query('encounters'), records);
      for (final op in response['accepted'] as List) {
        op['duplicate'] = true;
      }
      expect(await apply(), 0);
      expect(await repo.pendingOperations(), pending);
      expect((await repo.syncStatus())['last_successful_sync_at'], isNull);
    },
  );

  test(
    'partial receipt leaves rejected and missing operations untouched',
    () async {
      final accepted = response['accepted'] as List;
      final rejected = accepted.removeLast() as Map<String, dynamic>;
      accepted.removeLast();
      response['rejected'] = [
        {
          ...rejected,
          'error_code': 'missing_parent_operation',
          'message': 'Synthetic',
          'retryable': true,
        },
      ];
      expect(await apply(), 1);
      expect(await repo.pendingOperations(), hasLength(2));
    },
  );

  test(
    'foreign session, project and modified payload cannot mark records',
    () async {
      final original = batch;
      for (final field in ['worker_id', 'project_id', 'device_id', 'payload']) {
        final sent = jsonDecode(original.jsonBody) as Map<String, dynamic>;
        if (field == 'payload') {
          sent['operations'].last['payload']['client_code'] = '2026/MY/9999';
        } else {
          sent[field] = 'foreign';
        }
        batch = PreparedSyncBatch(jsonEncode(sent));
        await expectLater(apply(), throwsStateError);
        expect(await repo.pendingOperations(), hasLength(3));
      }
      batch = original;
      owner = null;
      await expectLater(apply(), throwsStateError);
      expect(
        (await db.connection.query(
          'sync_outbox',
        )).every((r) => r['acknowledged_at'] == null),
        isTrue,
      );
    },
  );

  test(
    'malformed receipt and missing local operation make no changes',
    () async {
      response['accepted'].last['revision'] = 99;
      await expectLater(apply(), throwsFormatException);
      response['accepted'].last['revision'] = 1;
      await db.connection.delete(
        'sync_outbox',
        where: 'operation_id = ?',
        whereArgs: [response['accepted'].last['operation_id']],
      );
      await expectLater(apply(), throwsStateError);
      expect(
        (await db.connection.query(
          'sync_outbox',
        )).every((r) => r['acknowledged_at'] == null),
        isTrue,
      );
    },
  );

  test(
    'SQLite failure halfway through marks rolls back all acknowledgements',
    () async {
      await db.connection.execute(
        "CREATE TRIGGER synthetic_failure BEFORE UPDATE ON sync_outbox WHEN NEW.operation_id = '${response['accepted'][1]['operation_id']}' BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
      );
      await expectLater(apply(), throwsA(isA<DatabaseException>()));
      expect(await repo.pendingOperations(), hasLength(3));
      expect(
        (await db.connection.query(
          'sync_outbox',
        )).every((r) => r['acknowledged_at'] == null),
        isTrue,
      );
    },
  );
}
