import 'package:ansvk_outreach/app.dart';
import 'package:ansvk_outreach/auth/auth_service.dart';
import 'package:ansvk_outreach/auth/session_controller.dart';
import 'package:ansvk_outreach/database/app_database.dart';
import 'package:ansvk_outreach/database/outreach_repository.dart';
import 'package:ansvk_outreach/hotspots/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'auth_test_support.dart';
import 'hotspot_test_support.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  late SessionController session;
  late OutreachRepository repo;
  var connections = 0;

  setUp(() async {
    db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    session = SessionController(AuthService(db, hasher: TestHasher()));
    repo = OutreachRepository(
      db,
      currentWorkerId: () => session.currentWorkerId,
    );
    await session.signIn('Alice', 'password1', register: true);
    connections = 0;
  });

  tearDown(() async {
    session.dispose();
    await db.close();
  });

  Future<void> flush(WidgetTester tester) async {
    for (var round = 0; round < 4; round++) {
      await tester.runAsync(() async {
        for (var i = 0; i < 10; i++) {
          await db.connection.rawQuery('SELECT 1');
        }
      });
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(
      OutreachApp(
        session: session,
        hasAccounts: true,
        location: HotspotLocationService(gateway: TestLocationGateway()),
        syncConnector: (_) async {
          connections++;
          throw StateError('Home and local navigation must not connect');
        },
      ),
    );
    await flush(tester);
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await flush(tester);
  }

  Future<List<List<Map<String, Object?>>>> storedData() async => [
    for (final table in [
      'workers',
      'hotspots',
      'encounters',
      'audit_operations',
      'sync_outbox',
      'sync_state',
      'dashboard_connection',
    ])
      await db.connection.query(table),
  ];

  testWidgets(
    'Today uses existing own-worker totals without writes or upload',
    (tester) async {
      late Map<String, Object?> summary, status;
      late List<List<Map<String, Object?>>> before;
      await tester.runAsync(() async {
        final first = await repo.createHotspot(name: 'River Road');
        final second = await repo.createHotspot(name: 'Market Lane');
        await repo.createEncounter({
          'hotspot_id': first,
          'client_code': '2026/MY/0001',
          'hiv': 'Reactive',
        });
        await repo.createEncounter({
          'hotspot_id': second,
          'client_code': '2026/MY/0001',
          'hiv': 'Non reactive',
        });
        final alice = session.currentWorkerId;
        session.logout();
        await session.signIn('Bob', 'password1', register: true);
        final other = await repo.createHotspot(name: 'Bob only');
        await repo.createEncounter({
          'hotspot_id': other,
          'client_code': '2026/MY/9999',
          'hiv': 'Reactive',
        });
        session.logout();
        await session.signIn('Alice', 'password1');
        expect(session.currentWorkerId, alice);
        summary = await repo.todaySummary();
        status = await repo.syncStatus();
        before = await storedData();
      });
      await start(tester);
      for (final field in [
        'unique_people',
        'client_records',
        'hotspots',
        'hiv_tested',
      ]) {
        final value = tester.widget<Text>(
          find.byKey(ValueKey('today-total-$field')),
        );
        expect(value.data, '${summary[field]}');
      }
      expect(summary['unique_people'], 1);
      expect(summary['client_records'], 2);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-pending-count')),
        150,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('today-home-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home-pending-count')))
            .data,
        '${status['pending_operations']} pending changes',
      );
      expect(find.text('No successful sync yet'), findsOneWidget);
      expect(await tester.runAsync(storedData), before);
      expect(connections, 0);
      session.logout();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'primary navigation and Add client use existing local destinations',
    (tester) async {
      late List<List<Map<String, Object?>>> before;
      await tester.runAsync(() async {
        await repo.createHotspot(name: 'River Road');
        before = await storedData();
      });
      await start(tester);
      await tap(tester, 'home-add-client');
      expect(find.text('Your hotspots'), findsOneWidget);
      expect(find.text('River Road'), findsOneWidget);
      await tap(tester, 'open-today-records');
      expect(find.text('No client records saved today.'), findsOneWidget);
      await tap(tester, 'open-sync-status');
      expect(find.text('Sync status'), findsOneWidget);
      await tap(tester, 'open-today-home');
      expect(find.byKey(const ValueKey('today-home-heading')), findsOneWidget);
      final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(nav.selectedIndex, 0);
      expect(await tester.runAsync(storedData), before);
      expect(connections, 0);
      session.logout();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'returning to Today refreshes totals and locked navigation stays hidden',
    (tester) async {
      final site = await tester.runAsync(
        () => repo.createHotspot(name: 'River Road'),
      );
      await start(tester);
      await tap(tester, 'open-hotspots');
      await tester.runAsync(
        () => repo.createEncounter({
          'hotspot_id': site,
          'client_code': '2026/MY/0004',
        }),
      );
      await tap(tester, 'open-today-home');
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('today-total-client_records')),
            )
            .data,
        '1',
      );
      session.lock();
      await tester.pump();
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byKey(const ValueKey('home-add-client')), findsNothing);
      await tester.runAsync(() => session.unlock('password1'));
      await flush(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(connections, 0);
      session.logout();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Today reflows on a narrow phone with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await start(tester);
    expect(find.byKey(const ValueKey('today-home-heading')), findsOneWidget);
    expect(tester.takeException(), isNull);
    session.logout();
    await tester.pumpWidget(const SizedBox());
  });
}
