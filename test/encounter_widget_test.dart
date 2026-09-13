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
  late AppDatabase database;
  late SessionController session;
  late OutreachRepository repository;

  setUp(() async {
    database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    session = SessionController(AuthService(database, hasher: TestHasher()));
    repository = OutreachRepository(
      database,
      currentWorkerId: () => session.currentWorkerId,
    );
  });

  tearDown(() async {
    session.dispose();
    await database.close();
  });

  Future<void> settleDatabase(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (var index = 0; index < 4; index++) {
        await database.connection.rawQuery('SELECT 1');
      }
    });
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(finder);
    await settleDatabase(tester);
  }

  Future<void> openEntry(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 2200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.runAsync(
      () => session.signIn('Alice', 'password1', register: true),
    );
    final hotspot = await tester.runAsync(
      () => repository.createHotspot(name: 'Entry site'),
    );
    await tester.pumpWidget(
      OutreachApp(
        session: session,
        hasAccounts: true,
        location: HotspotLocationService(gateway: TestLocationGateway()),
      ),
    );
    await tap(tester, find.byKey(const ValueKey('open-hotspots')));
    await tap(tester, find.byKey(ValueKey('hotspot-$hotspot')));
    await tap(tester, find.byKey(const ValueKey('open-client-entry')));
    expect(find.byKey(const ValueKey('save-encounter')), findsOneWidget);
  }

  testWidgets(
    'new client entry saves exact fields, then resets for next client',
    (tester) async {
      await openEntry(tester);
      await tap(tester, find.byKey(const ValueKey('save-encounter')));
      expect(find.text('Enter the client number.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('client-number')),
        '1',
      );
      await tap(tester, find.text('New'));
      expect(find.text('New client details'), findsOneWidget);
      await tap(tester, find.text('Save details'));
      expect(
        find.byKey(const ValueKey('edit-new-client-details')),
        findsOneWidget,
      );

      await tap(tester, find.byKey(const ValueKey('test-HIV')));
      await tap(tester, find.text('Reactive').last);
      await tester.enterText(find.byKey(const ValueKey('quantity-dist_3cc')), '2');
      await tester.enterText(
        find.byKey(const ValueKey('quantity-dist_condom')),
        '5',
      );
      await tap(tester, find.byKey(const ValueKey('refer-dic')));
      await tester.enterText(
        find.byKey(const ValueKey('remark')),
        'Follow up tomorrow',
      );
      await tap(tester, find.byKey(const ValueKey('save-encounter')));

      expect(find.text('Record saved. Enter the next client.'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('client-number')),
            )
            .controller!
            .text,
        isEmpty,
      );
      final records = await tester.runAsync(repository.encounters);
      expect(records, hasLength(1));
      final record = records!.single;
      expect(record['client_code'], '${DateTime.now().year}/MY/0001');
      expect(record['client_kind'], 'New');
      expect(record['user_type'], 'PWID');
      expect(record['hiv'], 'Reactive');
      expect(record['dist_3cc'], 2);
      expect(record['dist_condom'], 5);
      expect(record['refer_dic'], 1);
      expect(record['remark'], 'Follow up tomorrow');
      expect(await tester.runAsync(repository.pendingOperations), hasLength(3));
      session.logout();
    },
  );

  testWidgets('duplicate and invalid quantity keep the encounter form intact', (
    tester,
  ) async {
    await openEntry(tester);
    await tester.enterText(find.byKey(const ValueKey('client-number')), '2');
    await tester.enterText(find.byKey(const ValueKey('quantity-dist_1cc')), '-1');
    await tap(tester, find.byKey(const ValueKey('save-encounter')));
    expect(find.text('Enter zero or a whole number.'), findsOneWidget);
    expect(await tester.runAsync(repository.encounters), isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('quantity-dist_1cc')),
      '0',
    );
    await tap(tester, find.byKey(const ValueKey('save-encounter')));
    expect(await tester.runAsync(repository.encounters), hasLength(1));
    await tester.enterText(find.byKey(const ValueKey('client-number')), '2');
    await tap(tester, find.byKey(const ValueKey('save-encounter')));
    expect(
      find.text('This client already has a record for this hotspot today.'),
      findsOneWidget,
    );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('client-number')),
            )
            .controller!
            .text,
        '2',
      );
      session.logout();
  });
}
