import 'dart:convert';
import 'dart:io';

import 'package:ansvk_outreach/database/app_database.dart';
import 'package:ansvk_outreach/database/outreach_repository.dart';
import 'package:ansvk_outreach/sync/sync_batch_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  Future<Map<String, dynamic>> fixture(String name) async =>
      jsonDecode(
            await File(
              'docs/fixtures/outreach/v1/$name.request.json',
            ).readAsString(),
          )
          as Map<String, dynamic>;
  Map<String, Object?> identity(Map<String, dynamic> f) => {
    'project_id': f['project_id'],
    'project_name': f['project_name'],
    'device_id': f['device_id'],
    'created_at': f['device_created_at'],
  };
  List<Map<String, Object?>> rows(Map<String, dynamic> f) =>
      (f['operations'] as List)
          .map(
            (op) => <String, Object?>{
              ...op as Map<String, dynamic>,
              'payload': jsonEncode(op['payload']),
            },
          )
          .toList();
  SyncBatchBuilder builder(Map<String, dynamic> f) => SyncBatchBuilder(
    appVersion: f['app_version'] as String,
    clock: () => DateTime.parse(f['batch_created_at'] as String),
    newBatchId: () => f['batch_id'] as String,
  );
  for (final name in [
    'sync-create',
    'sync-revisions',
    'sync-partial',
    'sync-hotspot-no-gps',
  ]) {
    test('matches accepted $name request fixture exactly', () async {
      final f = await fixture(name);
      final prepared = builder(f).build(
        appIdentity: identity(f),
        workerId: f['worker_id'] as String,
        pendingOperations: rows(f),
      );
      expect(prepared, hasLength(1));
      expect(jsonDecode(prepared.single.jsonBody), f);
    });
  }
  test(
    'splits by 100 operations, preserving global sequence and immutable bytes',
    () async {
      final f = await fixture('sync-create');
      final base = rows(f).first;
      final input = List.generate(
        201,
        (i) => <String, Object?>{
          ...base,
          'sequence': i + 1,
          'operation_id': 'operation-$i',
        },
      ).reversed.toList();
      var id = 0;
      final plan =
          SyncBatchBuilder(
            appVersion: 'test',
            clock: () => DateTime.utc(2026),
            newBatchId: () => 'batch-${id++}',
          ).build(
            appIdentity: identity(f),
            workerId: f['worker_id'] as String,
            pendingOperations: input,
          );
      expect(
        plan.map((b) => (jsonDecode(b.jsonBody)['operations'] as List).length),
        [100, 100, 1],
      );
      expect(
        plan
            .expand((b) => jsonDecode(b.jsonBody)['operations'] as List)
            .map((op) => op['sequence']),
        List.generate(201, (i) => i + 1),
      );
      expect(
        plan.map((b) => jsonDecode(b.jsonBody)['batch_id']).toSet(),
        hasLength(3),
      );
      final saved = plan.first.jsonBody;
      input.first['payload'] = '{}';
      expect(plan.first.jsonBody, saved);
    },
  );
  test(
    'uses UTF-8 bytes for splitting and rejects a single oversized record',
    () async {
      final f = await fixture('sync-create');
      final op = rows(f).last;
      final payload =
          jsonDecode(op['payload'] as String) as Map<String, dynamic>;
      payload['remark'] = List.filled(150000, 'က').join();
      final input = List.generate(
        3,
        (i) => <String, Object?>{
          ...op,
          'sequence': i + 1,
          'operation_id': 'operation-$i',
          'payload': jsonEncode(payload),
        },
      );
      final plan = builder(f).build(
        appIdentity: identity(f),
        workerId: f['worker_id'] as String,
        pendingOperations: input,
      );
      expect(plan, hasLength(2));
      expect(
        plan.every((b) => b.byteLength <= SyncBatchBuilder.maxBytes),
        isTrue,
      );
      payload['remark'] = List.filled(400000, 'က').join();
      expect(
        () => builder(f).build(
          appIdentity: identity(f),
          workerId: f['worker_id'] as String,
          pendingOperations: [
            {...op, 'payload': jsonEncode(payload)},
          ],
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'rejects foreign ownership, duplicate IDs, malformed JSON and unknown secret fields',
    () async {
      final f = await fixture('sync-create');
      final op = rows(f).first;
      final payload =
          jsonDecode(op['payload'] as String) as Map<String, dynamic>;
      for (final input in <List<Map<String, Object?>>>[
        [
          {...op, 'actor_id': 'another-worker'},
        ],
        [
          op,
          {...op, 'sequence': 2},
        ],
        [
          {...op, 'payload': '{bad-json'},
        ],
        [
          {
            ...op,
            'payload': jsonEncode({...payload, 'password_hash': 'do-not-send'}),
          },
        ],
        [
          {
            ...op,
            'payload': jsonEncode({...payload, 'worker_id': 'another-worker'}),
          },
        ],
      ]) {
        expect(
          () => builder(f).build(
            appIdentity: identity(f),
            workerId: f['worker_id'] as String,
            pendingOperations: input,
          ),
          throwsFormatException,
        );
      }
      expect(
        builder(f).build(
          appIdentity: identity(f),
          workerId: f['worker_id'] as String,
          pendingOperations: [],
        ),
        isEmpty,
      );
    },
  );
  test(
    'prepares real repository create/update/delete queue without changing outbox or audit',
    () async {
      sqfliteFfiInit();
      final db = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      addTearDown(db.close);
      String? worker;
      final repo = OutreachRepository(db, currentWorkerId: () => worker);
      worker = await repo.createWorkerProfile('synthetic');
      final hotspot = await repo.createHotspot(
        name: 'Synthetic',
        peers: ['Peer 1', 'Peer 2'],
      );
      final encounter = await repo.createEncounter({
        'hotspot_id': hotspot,
        'client_code': '2026/MY/0001',
      });
      await repo.updateEncounter(encounter, {
        'remark': 'updated',
      }, expectedRevision: 1);
      await repo.deleteEncounter(encounter, expectedRevision: 2);
      final before = await repo.pendingOperations();
      final plan =
          SyncBatchBuilder(
            appVersion: 'test',
            clock: () => DateTime.utc(2026),
          ).build(
            appIdentity: await repo.appIdentity(),
            workerId: worker,
            pendingOperations: before,
          );
      expect(
        (jsonDecode(plan.single.jsonBody)['operations'] as List),
        hasLength(5),
      );
      expect(await repo.pendingOperations(), before);
      expect(
        (await db.connection.query(
          'sync_outbox',
        )).every((r) => r['acknowledged_at'] == null),
        isTrue,
      );
    },
  );
}
