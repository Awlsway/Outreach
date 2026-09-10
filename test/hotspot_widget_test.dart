import 'dart:async';
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
  late TestLocationGateway gps;
  late OutreachRepository repo;
  setUp(() async {
    db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    session = SessionController(AuthService(db, hasher: TestHasher()));
    gps = TestLocationGateway();
    repo = OutreachRepository(
      db,
      currentWorkerId: () => session.currentWorkerId,
    );
  });
  tearDown(() async {
    session.dispose();
    await db.close();
  });

  Future<void> flush(WidgetTester tester) async {
    await tester.runAsync(() async {
      // Drain serialized SQLite work and its Dart completion callbacks.
      for (var i = 0; i < 4; i++) {
        await db.connection.rawQuery('SELECT 1');
      }
    });
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(finder);
    await flush(tester);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> start(WidgetTester tester) async {
    await tester.runAsync(
      () => session.signIn('Alice', 'password1', register: true),
    );
    await tester.pumpWidget(
      OutreachApp(
        session: session,
        hasAccounts: true,
        location: HotspotLocationService(gateway: gps),
      ),
    );
    await tap(tester, find.byKey(const ValueKey('open-hotspots')));
  }

  testWidgets(
    'create two hotspots, search, select and show saved peers/coordinates',
    (tester) async {
      await start(tester);
      expect(
        find.text('No hotspots yet. Create your first hotspot.'),
        findsOneWidget,
      );
      await tap(tester, find.byKey(const ValueKey('new-hotspot')));
      expect(find.text('Location captured'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('hotspot-name')),
        'Hotspot A',
      );
      await tester.enterText(find.byKey(const ValueKey('peer-0')), 'Peer One');
      await tap(tester, find.byKey(const ValueKey('add-peer')));
      await tester.enterText(find.byKey(const ValueKey('peer-1')), 'Peer Two');
      await tap(tester, find.byKey(const ValueKey('save-hotspot')));
      expect(find.text('Hotspot A'), findsOneWidget);
      expect(find.text('Peer One, Peer Two'), findsOneWidget);
      gps.serviceEnabled = false;
      await tap(tester, find.byKey(const ValueKey('new-hotspot')));
      expect(find.text('GPS unavailable'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('hotspot-name')),
        'Hotspot B',
      );
      await tap(tester, find.byKey(const ValueKey('save-hotspot')));
      expect(find.text('Hotspot A'), findsOneWidget);
      expect(find.text('Hotspot B'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('search-hotspots')),
        'spot a',
      );
      await flush(tester);
      expect(find.text('Hotspot A'), findsOneWidget);
      expect(find.text('Hotspot B'), findsNothing);
      await tap(tester, find.text('Hotspot A'));
      expect(find.text('Selected hotspot'), findsOneWidget);
      expect(find.text('Peer One'), findsOneWidget);
      expect(find.text('Peer Two'), findsOneWidget);
      expect(find.text('Latitude: 16.800000'), findsOneWidget);
      expect(find.text('Longitude: 96.100000'), findsOneWidget);
      final rows = await tester.runAsync(repo.hotspots);
      expect(rows, hasLength(2));
      expect(rows![1]['latitude'], isNull);
      expect(rows[1]['longitude'], isNull);
      expect(rows[1]['location_status'], 'Unavailable');
      expect(
        gps.positions,
        1,
      ); // Selection and list navigation never capture GPS.
      session.logout();
    },
  );

  testWidgets(
    'draft survives lock and failed permission; other account has an empty list',
    (tester) async {
      gps.serviceEnabled = false;
      await start(tester);
      await tap(tester, find.byKey(const ValueKey('new-hotspot')));
      await tester.enterText(
        find.byKey(const ValueKey('hotspot-name')),
        'Draft A',
      );
      await tester.enterText(find.byKey(const ValueKey('peer-0')), 'Peer One');
      session.lock();
      await tester.pump();
      expect(find.text('App locked'), findsOneWidget);
      expect(find.byKey(const ValueKey('hotspot-name')), findsNothing);
      await tester.runAsync(() => session.unlock('password1'));
      await tester.pump();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('hotspot-name')))
            .controller!
            .text,
        'Draft A',
      );
      await tap(tester, find.byKey(const ValueKey('save-hotspot')));
      expect(find.text('Draft A'), findsOneWidget);
      session.logout();
      await tester.pump();
      await tester.runAsync(
        () => session.signIn('Bob', 'password2', register: true),
      );
      await tester.pump();
      await tap(tester, find.byKey(const ValueKey('open-hotspots')));
      expect(find.text('Draft A'), findsNothing);
      expect(
        find.text('No hotspots yet. Create your first hotspot.'),
        findsOneWidget,
      );
      session.logout();
      await tester.pump();
      await tester.runAsync(() => session.signIn('Alice', 'password1'));
      await tester.pump();
      await tap(tester, find.byKey(const ValueKey('open-hotspots')));
      expect(find.text('Draft A'), findsOneWidget);
      session.logout();
    },
  );

  testWidgets(
    'skipping a pending fix saves null coordinates and ignores late results',
    (tester) async {
      gps.pending = Completer<LocationCapture>();
      await start(tester);
      await tap(tester, find.byKey(const ValueKey('new-hotspot')));
      await tester.enterText(
        find.byKey(const ValueKey('hotspot-name')),
        'Skipped',
      );
      await tap(tester, find.text('Continue without GPS'));
      gps.pending!.complete(const LocationCapture.available(1, 2));
      await tester.pump();
      expect(find.text('GPS unavailable'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('save-hotspot')));
      final rows = await tester.runAsync(repo.hotspots);
      expect(rows!.single['latitude'], isNull);
      expect(rows.single['location_status'], 'Unavailable');
      session.logout();
    },
  );
}
