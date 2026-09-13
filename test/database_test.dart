import 'dart:io';

import 'package:ansvk_outreach/database/app_database.dart';
import 'package:ansvk_outreach/database/outreach_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late AppDatabase database;
  late OutreachRepository repo;
  late String worker;
  late String hotspot;
  String? session;
  var now = DateTime(2026, 9, 10, 10);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ansvk_db_test_');
    database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/test.db',
    );
    now = DateTime(2026, 9, 10, 10);
    session = null;
    repo = OutreachRepository(
      database,
      currentWorkerId: () => session,
      clock: () => now,
    );
    worker = await repo.createWorkerProfile('worker1');
    session = worker;
    hotspot = await repo.createHotspot(
      name: 'Site X',
      peers: [' Peer 1 ', 'Peer 2'],
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'schema initializes, foreign keys enabled, data persists on reopen',
    () async {
      final id = await repo.createEncounter({
        'hotspot_id': hotspot,
        'client_code': ' 001 ',
      });
      expect(await database.connection.getVersion(), 4);
      expect(
        (await database.connection.rawQuery(
          'PRAGMA foreign_keys',
        )).single.values.single,
        1,
      );
      final tables = await database.connection.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      expect(
        tables.map((r) => r['name']),
        containsAll([
          'workers',
          'hotspots',
          'hotspot_peers',
          'encounters',
          'audit_operations',
          'sync_outbox',
          'sync_state',
          'credentials',
          'app_identity',
          'dashboard_connection',
        ]),
      );
      final identity = await repo.appIdentity();
      expect(identity['singleton_id'], 1);
      expect(identity['project_id'], 'ansvk_outreach');
      expect(identity['project_name'], 'ANSVK Outreach');
      expect(identity['device_id'], isA<String>());
      expect((identity['device_id'] as String).length, greaterThan(20));
      expect(DateTime.tryParse(identity['created_at'] as String), isNotNull);
      await database.close();
      database = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/test.db',
      );
      repo = OutreachRepository(
        database,
        currentWorkerId: () => session,
        clock: () => now,
      );
      expect(await repo.appIdentity(), identity);
      final row = (await repo.encounter(id))!;
      expect(row['client_code'], '001');
      expect(row['dist_3cc'], 0);
      expect(row['hiv'], 'No');
      expect(row['refer_dic'], 0);
      expect((await repo.hotspots()).single['peers'], ['Peer 1', 'Peer 2']);
      expect(await repo.pendingOperations(), hasLength(3));
      final status = await repo.syncStatus();
      expect(status['pending_operations'], 3);
      expect(status['pending_workers'], 1);
      expect(status['pending_hotspots'], 1);
      expect(status['pending_encounters'], 1);
      expect(status['pending_creates'], 3);
      expect(status['pending_updates'], 0);
      expect(status['pending_deletes'], 0);
      expect(status['last_successful_sync_at'], isNull);
      expect(status['project_id'], 'ansvk_outreach');
      expect(status['project_name'], 'ANSVK Outreach');
      expect(status['device_id'], identity['device_id']);
      expect(status['dashboard_status'], 'Not configured');
      expect(status['dashboard_url'], isNull);
      expect(status['paired_at'], isNull);
      await repo.saveDashboardAddress(' http://192.168.1.20:8080/api/v1 ');
      final configured = await repo.syncStatus();
      expect(configured['dashboard_status'], 'Not configured');
      expect(configured['dashboard_url'], 'http://192.168.1.20:8080/api/v1');
      expect(configured['dashboard_id'], isNull);
      expect(configured['paired_at'], isNull);
      await repo.clearDashboardAddress();
      final cleared = await repo.syncStatus();
      expect(cleared['dashboard_status'], 'Not configured');
      expect(cleared['dashboard_url'], isNull);
      expect(cleared['dashboard_id'], isNull);
      expect(cleared['paired_at'], isNull);
      expect(
        await database.connection.rawQuery('PRAGMA foreign_key_check'),
        isEmpty,
      );
      expect(
        (await database.connection.rawQuery(
          'PRAGMA integrity_check',
        )).single.values.single,
        'ok',
      );
    },
  );

  test(
    'duplicate key rejects repeated saves and allows other sites/days/workers',
    () async {
      final input = {'hotspot_id': hotspot, 'client_code': 'A'};
      await repo.createEncounter(input);
      await expectLater(
        repo.createEncounter(input),
        throwsA(isA<DatabaseException>()),
      );
      final y = await repo.createHotspot(name: 'Site Y');
      await repo.createEncounter({'hotspot_id': y, 'client_code': 'A'});
      now = DateTime(2026, 9, 11);
      await repo.createEncounter(input);
      session = await repo.createWorkerProfile('worker2');
      final z = await repo.createHotspot(name: 'Site X');
      await repo.createEncounter({'hotspot_id': z, 'client_code': 'A'});
      expect(await repo.encounters(), hasLength(1));
    },
  );

  test(
    'ownership rejects cross-worker references, reads and mutations',
    () async {
      final id = await repo.createEncounter({
        'hotspot_id': hotspot,
        'client_code': 'A',
      });
      session = await repo.createWorkerProfile('worker2');
      expect(await repo.encounters(), isEmpty);
      expect(await repo.hotspots(), isEmpty);
      expect(await repo.encounter(id), isNull);
      await expectLater(
        repo.createEncounter({'hotspot_id': hotspot, 'client_code': 'A'}),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        repo.updateEncounter(id, {'remark': 'bad'}, expectedRevision: 1),
        throwsStateError,
      );
      await expectLater(
        repo.deleteEncounter(id, expectedRevision: 1),
        throwsStateError,
      );
      final ownSite = await repo.createHotspot(name: 'Own');
      final ownId = await repo.createEncounter({
        'hotspot_id': ownSite,
        'client_code': 'A',
      });
      await expectLater(
        repo.updateEncounter(ownId, {
          'hotspot_id': hotspot,
        }, expectedRevision: 1),
        throwsA(isA<DatabaseException>()),
      );
      session = null;
      expect(() => repo.encounters(), throwsStateError);
    },
  );

  test(
    'SQL validates quantities, categories, location, and required code',
    () async {
      for (final changes in <Row>[
        {'client_code': ''},
        {'dist_3cc': -1},
        {'recollect_1cc': 1.5},
        {'hiv': 'invalid'},
        {'refer_dic': 2},
        {'client_kind': 'invalid'},
        {'client_kind': 'New', 'gender': 'invalid'},
      ]) {
        await expectLater(
          repo.createEncounter({
            'hotspot_id': hotspot,
            'client_code': 'A',
            ...changes,
          }),
          throwsA(isA<DatabaseException>()),
        );
      }
      await expectLater(
        repo.createHotspot(name: 'Bad', latitude: 10),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        repo.createHotspot(name: 'Bad', latitude: 91, longitude: 0),
        throwsA(isA<DatabaseException>()),
      );
      expect(await repo.encounters(), isEmpty);
      expect(await repo.pendingOperations(), hasLength(2));
    },
  );

  test(
    'New defaults stored, changing to Old clears previous client information',
    () async {
      final id = await repo.createEncounter({
        'hotspot_id': hotspot,
        'client_code': 'A',
        'client_kind': 'New',
      });
      final row = (await repo.encounter(id))!;
      expect(row['user_type'], 'PWID');
      expect(row['previous_hiv'], 'Unknown');
      expect(row['previous_mmt'], 'No');
      expect(row['gender'], isNull);
      now = DateTime(2026, 9, 11);
      await repo.updateEncounter(id, {
        'client_kind': 'Old',
      }, expectedRevision: 1);
      final after = (await repo.encounter(id))!;
      expect(after['previous_hiv'], isNull);
      expect(after['user_type'], isNull);
      expect(after['visit_date'], '2026-09-10');
      expect(after['revision'], 2);
      await expectLater(
        repo.updateEncounter(id, {'remark': 'stale'}, expectedRevision: 1),
        throwsStateError,
      );
      await expectLater(
        repo.updateEncounter(id, {
          'visit_date': '2026-01-01',
        }, expectedRevision: 2),
        throwsArgumentError,
      );
      await expectLater(
        repo.createEncounter({
          'hotspot_id': hotspot,
          'client_code': 'B',
          'owner_id': worker,
        }),
        throwsArgumentError,
      );
    },
  );

  test('edit duplicate rejected and tombstone permits replacement', () async {
    final a = await repo.createEncounter({
      'hotspot_id': hotspot,
      'client_code': 'A',
    });
    final b = await repo.createEncounter({
      'hotspot_id': hotspot,
      'client_code': 'B',
    });
    await expectLater(
      repo.updateEncounter(b, {'client_code': 'A'}, expectedRevision: 1),
      throwsA(isA<DatabaseException>()),
    );
    expect((await repo.encounter(b))!['revision'], 1);
    await repo.deleteEncounter(a, expectedRevision: 1);
    expect(await repo.encounter(a), isNull);
    await repo.createEncounter({'hotspot_id': hotspot, 'client_code': 'A'});
    final operations = await repo.pendingOperations();
    expect(
      operations.where((r) => r['entity_id'] == a).map((r) => r['action']),
      ['create', 'delete'],
    );
    expect(operations.every((r) => r['actor_id'] == worker), isTrue);
  });

  test('outbox failure rolls back encounter, audit, and edits', () async {
    final id = await repo.createEncounter({
      'hotspot_id': hotspot,
      'client_code': 'A',
    });
    final count = (await repo.pendingOperations()).length;
    await database.connection.execute(
      '''CREATE TRIGGER fail_queue BEFORE INSERT ON sync_outbox
      BEGIN SELECT RAISE(ABORT, 'Simulated queue failure'); END''',
    );
    await expectLater(
      repo.createEncounter({'hotspot_id': hotspot, 'client_code': 'B'}),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      repo.updateEncounter(id, {'remark': 'lost'}, expectedRevision: 1),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      repo.deleteEncounter(id, expectedRevision: 1),
      throwsA(isA<DatabaseException>()),
    );
    expect(await repo.encounters(), hasLength(1));
    expect((await repo.encounter(id))!['revision'], 1);
    expect(await repo.pendingOperations(), hasLength(count));
    expect(
      await database.connection.query('audit_operations'),
      hasLength(count),
    );
  });

  test(
    'unique daily people count across sites updates correctly after deletes',
    () async {
      final y = await repo.createHotspot(name: 'Y');
      final a1 = await repo.createEncounter({
        'hotspot_id': hotspot,
        'client_code': 'A',
        'client_kind': 'New',
        'hiv': 'Non reactive',
        'hcv': 'Reactive',
        'dist_3cc': 2,
        'dist_condom': 4,
        'recollect_lds': 1,
        'refer_dic': 1,
      });
      await repo.createEncounter({
        'hotspot_id': y,
        'client_code': 'A',
        'client_kind': 'Old',
        'hiv': 'Reactive',
        'hbv': 'Non reactive',
        'dist_3cc': 3,
      });
      final b = await repo.createEncounter({
        'hotspot_id': hotspot,
        'client_code': 'B',
        'syphilis': 'Reactive',
      });
      now = DateTime(2026, 9, 9);
      await repo.createEncounter({'hotspot_id': hotspot, 'client_code': 'C'});
      now = DateTime(2026, 9, 10);
      final summary = await repo.todaySummary();
      expect(summary['client_records'], 3);
      expect(summary['unique_people'], 2);
      expect(summary['hotspots'], 2);
      expect(summary['new_clients'], 1);
      expect(summary['old_clients'], 1);
      expect(summary['unspecified_clients'], 1);
      expect(summary['hiv_tested'], 2);
      expect(summary['hiv_reactive'], 1);
      expect(summary['hcv_tested'], 1);
      expect(summary['hcv_reactive'], 1);
      expect(summary['hbv_tested'], 1);
      expect(summary['hbv_reactive'], 0);
      expect(summary['syphilis_tested'], 1);
      expect(summary['syphilis_reactive'], 1);
      expect(summary['dic_referrals'], 1);
      expect(summary['dist_3cc'], 5);
      expect(summary['dist_condom'], 4);
      expect(summary['recollect_lds'], 1);
      await repo.deleteEncounter(b, expectedRevision: 1);
      expect((await repo.todaySummary())['unique_people'], 1);
      await repo.deleteEncounter(a1, expectedRevision: 1);
      expect((await repo.todaySummary())['unique_people'], 1);
      session = await repo.createWorkerProfile('worker2');
      expect((await repo.todaySummary())['unique_people'], 0);
    },
  );

  test('concurrent duplicate attempts commit once', () async {
    final outcomes = await Future.wait(
      List.generate(2, (_) async {
        try {
          await repo.createEncounter({
            'hotspot_id': hotspot,
            'client_code': 'A',
          });
          return true;
        } on DatabaseException {
          return false;
        }
      }),
    );
    expect(outcomes.where((ok) => ok), hasLength(1));
    expect(await repo.encounters(), hasLength(1));
    expect(await repo.pendingOperations(), hasLength(3));
  });
}
