import 'dart:async';

import 'package:ansvk_outreach/app.dart';
import 'package:ansvk_outreach/auth/auth_service.dart';
import 'package:ansvk_outreach/auth/session_controller.dart';
import 'package:ansvk_outreach/database/app_database.dart';
import 'package:ansvk_outreach/database/outreach_repository.dart' hide Row;
import 'package:ansvk_outreach/encounters/encounter_form.dart';
import 'package:ansvk_outreach/hotspots/location_service.dart';
import 'package:ansvk_outreach/hotspots/new_hotspot_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'auth_test_support.dart';
import 'hotspot_test_support.dart';

class PendingSaveRepository extends OutreachRepository {
  PendingSaveRepository(super.database, {required super.currentWorkerId});
  final saved = Completer<void>();

  @override
  Future<String> createHotspot({
    required String name,
    List<String> peers = const [],
    double? latitude,
    double? longitude,
  }) async {
    await saved.future;
    return 'saved-hotspot';
  }

  @override
  Future<String> createEncounter(Map<String, Object?> input) async {
    await saved.future;
    return 'saved-encounter';
  }

  @override
  Future<void> updateEncounter(
    String id,
    Map<String, Object?> changes, {
    required int expectedRevision,
  }) => saved.future;
}

void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  late SessionController session;
  late OutreachRepository repo;
  late TestLocationGateway gps;
  var connections = 0;

  setUp(() async {
    db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    session = SessionController(AuthService(db, hasher: TestHasher()));
    await session.signIn('Alice', 'password1', register: true);
    repo = OutreachRepository(
      db,
      currentWorkerId: () => session.currentWorkerId,
    );
    gps = TestLocationGateway();
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
        location: HotspotLocationService(gateway: gps),
        syncConnector: (_) async {
          connections++;
          throw StateError('Local journeys must not connect');
        },
      ),
    );
    await flush(tester);
    await tester.tap(find.byKey(const ValueKey('open-hotspots')));
    await flush(tester);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        180,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pump();
    // Helper text can change the lazy list's final scroll extent.
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await flush(tester);
  }

  Future<void> back(WidgetTester tester, bool system) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    if (system) {
      await tester.binding.handlePopRoute();
    } else {
      await tester.tap(find.byType(BackButton).first);
    }
    await flush(tester);
  }

  Future<List<List<Map<String, Object?>>>> stored() async => [
    for (final table in [
      'hotspots',
      'hotspot_peers',
      'encounters',
      'audit_operations',
      'sync_outbox',
    ])
      await db.connection.query(table),
  ];

  Future<void> finish(WidgetTester tester) async {
    session.logout();
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets(
    'row shortcut and detail entry use the correct hotspot and Back origin',
    (tester) async {
      final id = await tester.runAsync(
        () => repo.createHotspot(
          name: 'River Road',
          peers: ['Peer A'],
          latitude: 16.8,
          longitude: 96.1,
        ),
      );
      final before = await tester.runAsync(stored);
      await start(tester);
      for (final system in [false, true]) {
        await tap(tester, find.byKey(ValueKey('add-client-$id')));
        expect(find.text('Client entry'), findsOneWidget);
        expect(find.text('River Road'), findsOneWidget);
        expect(find.text('Selected hotspot'), findsNothing);
        await back(tester, system);
        expect(find.text('Your hotspots'), findsOneWidget);
        await tap(tester, find.byKey(ValueKey('hotspot-details-$id')));
        expect(find.text('Latitude: 16.800000'), findsOneWidget);
        await tap(tester, find.byKey(const ValueKey('open-client-entry')));
        await back(tester, system);
        expect(find.text('Selected hotspot'), findsOneWidget);
        await back(tester, system);
      }
      expect(await tester.runAsync(stored), before);
      expect(gps.positions, 0);
      expect(connections, 0);
      await finish(tester);
    },
  );

  testWidgets(
    'new hotspot offers immediate entry and is created exactly once',
    (tester) async {
      await start(tester);
      await tester.enterText(
        find.byKey(const ValueKey('search-hotspots')),
        'Does not match',
      );
      await flush(tester);
      await tap(tester, find.byKey(const ValueKey('new-hotspot')));
      await tester.enterText(
        find.byKey(const ValueKey('hotspot-name')),
        'Fresh hotspot',
      );
      await tester.enterText(find.byKey(const ValueKey('peer-0')), 'Peer A');
      await tap(tester, find.byKey(const ValueKey('save-hotspot')));
      expect(find.text('Hotspot saved'), findsOneWidget);
      expect(find.text('Fresh hotspot'), findsOneWidget);
      final rows = await tester.runAsync(repo.hotspots);
      expect(rows, hasLength(1));
      expect(rows!.single['peers'], ['Peer A']);
      expect(rows.single['latitude'], 16.8);
      final before = await tester.runAsync(stored);
      await tap(tester, find.byKey(const ValueKey('add-client-here')));
      expect(find.text('Client entry'), findsOneWidget);
      expect(find.text('Fresh hotspot'), findsOneWidget);
      await back(tester, true);
      expect(find.text('Hotspot saved'), findsOneWidget);
      await back(tester, false);
      expect(find.text('Your hotspots'), findsOneWidget);
      expect(find.text('Fresh hotspot'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('search-hotspots')))
            .controller!
            .text,
        isEmpty,
      );
      expect(await tester.runAsync(stored), before);
      final operations = await tester.runAsync(repo.pendingOperations);
      expect(
        operations!.where((row) => row['entity_type'] == 'hotspot'),
        hasLength(1),
      );
      expect(
        operations.where((row) => row['entity_type'] == 'encounter'),
        isEmpty,
      );
      expect(gps.positions, 1);
      expect(connections, 0);
      await finish(tester);
    },
  );

  testWidgets('create form Back returns to the list without saving a draft', (
    tester,
  ) async {
    await start(tester);
    final before = await tester.runAsync(stored);
    for (final system in [false, true]) {
      await tap(tester, find.byKey(const ValueKey('new-hotspot')));
      await tester.enterText(
        find.byKey(const ValueKey('hotspot-name')),
        'Unsaved',
      );
      await back(tester, system);
      expect(find.text('Your hotspots'), findsOneWidget);
    }
    expect(await tester.runAsync(stored), before);
    await finish(tester);
  });

  testWidgets(
    'edit Back returns to record detail and leaves the saved record untouched',
    (tester) async {
      late String id;
      await tester.runAsync(() async {
        final hotspot = await repo.createHotspot(name: 'River Road');
        id = await repo.createEncounter({
          'hotspot_id': hotspot,
          'client_code': '2026/MY/0042',
        });
      });
      final before = await tester.runAsync(stored);
      await start(tester);
      await tap(tester, find.byKey(const ValueKey('open-today-records')));
      await tap(tester, find.byKey(ValueKey('record-$id')));
      for (final system in [false, true]) {
        await tap(tester, find.byKey(const ValueKey('edit-record')));
        expect(find.text('Edit record'), findsOneWidget);
        await back(tester, system);
        expect(find.text('Record detail'), findsOneWidget);
      }
      expect(await tester.runAsync(stored), before);
      expect(connections, 0);
      await finish(tester);
    },
  );

  testWidgets('hotspot actions fit a narrow phone with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final id = await tester.runAsync(
      () => repo.createHotspot(
        name: 'River Road community hotspot',
        peers: ['Peer A', 'Peer B'],
      ),
    );
    await start(tester);
    expect(find.byKey(ValueKey('add-client-$id')), findsOneWidget);
    expect(find.byKey(ValueKey('hotspot-details-$id')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  for (final kind in ['hotspot', 'encounter', 'edit']) {
    testWidgets('both Back controls stay guarded during $kind save', (
      tester,
    ) async {
      final pending = PendingSaveRepository(
        db,
        currentWorkerId: () => session.currentWorkerId,
      );
      var backs = 0;
      var saved = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: kind == 'hotspot'
              ? NewHotspotForm(
                  repository: pending,
                  session: session,
                  location: HotspotLocationService(gateway: gps),
                  onSaved: (_) => saved++,
                  onBack: () => backs++,
                )
              : EncounterForm(
                  repository: pending,
                  session: session,
                  hotspot: const {'hotspot_id': 'site', 'name': 'River Road'},
                  initialRecord: kind == 'edit'
                      ? const {
                          'encounter_id': 'record',
                          'client_code': '2026/MY/0042',
                          'revision': 1,
                        }
                      : null,
                  onSaved: () => saved++,
                  onBack: () => backs++,
                ),
        ),
      );
      await flush(tester);
      if (kind == 'hotspot') {
        await tester.enterText(
          find.byKey(const ValueKey('hotspot-name')),
          'Busy',
        );
      } else if (kind == 'encounter') {
        await tester.enterText(
          find.byKey(const ValueKey('client-number')),
          '42',
        );
      }
      final saveKey = kind == 'hotspot' ? 'save-hotspot' : 'save-encounter';
      await tap(tester, find.byKey(ValueKey(saveKey)));
      await back(tester, false);
      await back(tester, true);
      expect(backs, 0);
      expect(saved, 0);
      pending.saved.complete();
      await flush(tester);
      expect(
        kind == 'encounter'
            ? find
                  .text('Record saved. Enter the next client.')
                  .evaluate()
                  .isNotEmpty
            : saved == 1,
        isTrue,
      );
      await finish(tester);
    });
  }
}
