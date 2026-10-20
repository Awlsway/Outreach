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
  late String hotspot;

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
    hotspot = await repo.createHotspot(name: 'River Road');
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

  Future<void> tap(WidgetTester tester, Finder finder) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await flush(tester);
  }

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      OutreachApp(
        session: session,
        hasAccounts: true,
        location: HotspotLocationService(gateway: TestLocationGateway()),
      ),
    );
    await flush(tester);
    await tap(tester, find.byKey(const ValueKey('open-hotspots')));
    await tap(tester, find.byKey(ValueKey('add-client-$hotspot')));
  }

  ScrollController scroll(WidgetTester tester) => tester
      .widget<SingleChildScrollView>(
        find.byKey(const ValueKey('client-entry-scroll')),
      )
      .controller!;

  Future<void> bottom(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    scroll(tester).jumpTo(scroll(tester).position.maxScrollExtent);
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    session.logout();
    await tester.pumpWidget(const SizedBox());
  }

  final save = find.byKey(const ValueKey('save-encounter'));

  testWidgets(
    'clear test labels preserve stored No values and compact supply rows',
    (tester) async {
      await start(tester);
      final semantics = tester.ensureSemantics();
      try {
        expect(find.text('Not tested'), findsNWidgets(4));
        for (final disease in ['HIV', 'HCV', 'HBV', 'Syphilis']) {
          expect(
            tester
                .state<FormFieldState<String>>(
                  find.byKey(ValueKey('test-$disease')),
                )
                .value,
            'No',
          );
        }
        await tester.ensureVisible(find.byKey(const ValueKey('test-HIV')));
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsLabel(RegExp('HIV test result')),
          findsOneWidget,
        );
        final first = find.byKey(const ValueKey('quantity-dist_3cc'));
        await tester.ensureVisible(first);
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsLabel(RegExp('Distribution 3cc')),
          findsOneWidget,
        );
        expect(
          tester.getTopLeft(first).dy,
          tester.getTopLeft(find.byKey(const ValueKey('quantity-dist_1cc'))).dy,
        );
        expect(
          tester.getTopLeft(first).dy,
          tester.getTopLeft(find.byKey(const ValueKey('quantity-dist_lds'))).dy,
        );
        await tester.enterText(
          find.byKey(const ValueKey('client-number')),
          '47',
        );
        await tap(tester, save);
        final record = (await tester.runAsync(repo.encounters))!.single;
        for (final field in ['hiv', 'hcv', 'hbv', 'syphilis']) {
          expect(record[field], 'No');
        }
        expect(record['dist_3cc'], 0);
        expect(record['client_kind'], isNull);
        await finish(tester);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'large text stacks choices and supplies without changing input or validation',
    (tester) async {
      await start(tester);
      tester.view.physicalSize = const Size(320, 844);
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SegmentedButton<String>>(
              find.byKey(const ValueKey('client-kind')),
            )
            .direction,
        Axis.vertical,
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('client-number'))).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const ValueKey('client-year'))).dy,
        ),
      );
      final first = find.byKey(const ValueKey('quantity-dist_3cc'));
      final second = find.byKey(const ValueKey('quantity-dist_1cc'));
      await tester.ensureVisible(first);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(second).dy,
        greaterThan(tester.getTopLeft(first).dy),
      );
      await tester.enterText(second, '-1');
      await tap(tester, save);
      expect(find.text('Enter the client number.'), findsOneWidget);
      expect(find.text('Enter zero or a whole number.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(await tester.runAsync(repo.encounters), isEmpty);
      expect(await tester.runAsync(repo.pendingOperations), hasLength(2));
      await finish(tester);
    },
  );

  testWidgets(
    'new-client details remain readable with large text and retain defaults',
    (tester) async {
      await start(tester);
      tester.view.physicalSize = const Size(320, 844);
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('New'));
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      expect(find.text('New client details'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Save details'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('client-number')), '48');
      await tap(tester, save);
      final record = (await tester.runAsync(repo.encounters))!.single;
      expect(record['client_kind'], 'New');
      expect(record['user_type'], 'PWID');
      expect(record['gender'], isNull);
      expect(record['previous_hiv'], 'Unknown');
      expect(record['previous_hcv'], 'Unknown');
      expect(record['previous_hbv'], 'Unknown');
      expect(record['previous_mmt'], 'No');
      expect(record['previous_art'], 'No');
      await finish(tester);
    },
  );

  void expectErrorVisible(WidgetTester tester, String message) {
    final error = find.text(message);
    expect(error, findsOneWidget);
    final viewport = tester.getRect(
      find.byKey(const ValueKey('client-entry-scroll')),
    );
    final bounds = tester.getRect(error);
    expect(bounds.top, greaterThanOrEqualTo(viewport.top));
    expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom));
  }

  testWidgets('Save stays visible while scrolling and above the keyboard', (
    tester,
  ) async {
    await start(tester);
    final original = tester.getRect(save);
    await bottom(tester);
    expect(tester.getRect(save), original);
    expect(save.hitTestable(), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    final lifted = tester.getRect(save);
    expect(lifted.top, greaterThan(0));
    expect(lifted.bottom, lessThanOrEqualTo(544));
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('Save reveals the same missing-code validation from the bottom', (
    tester,
  ) async {
    await start(tester);
    await bottom(tester);
    await tap(tester, save);
    expectErrorVisible(tester, 'Enter the client number.');
    expect(await tester.runAsync(repo.encounters), isEmpty);
    await finish(tester);
  });

  testWidgets(
    'Save reveals the existing quantity error without correcting its value',
    (tester) async {
      await start(tester);
      await tester.enterText(find.byKey(const ValueKey('client-number')), '45');
      await tester.enterText(
        find.byKey(const ValueKey('quantity-dist_1cc')),
        '-1',
      );
      scroll(tester).jumpTo(0);
      await tester.pump();
      await tap(tester, save);
      expectErrorVisible(tester, 'Enter zero or a whole number.');
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('quantity-dist_1cc')),
            )
            .controller!
            .text,
        '-1',
      );
      expect(await tester.runAsync(repo.encounters), isEmpty);
      await finish(tester);
    },
  );

  testWidgets(
    'successful save returns to client code and visibly resets the same defaults',
    (tester) async {
      await start(tester);
      await tester.enterText(find.byKey(const ValueKey('client-number')), '45');
      await tap(tester, find.byKey(const ValueKey('test-HIV')));
      await tap(tester, find.text('Reactive').last);
      await tester.enterText(
        find.byKey(const ValueKey('quantity-dist_3cc')),
        '7',
      );
      await bottom(tester);
      await tap(tester, save);
      expect(scroll(tester).offset, 0);
      final number = tester.widget<TextFormField>(
        find.byKey(const ValueKey('client-number')),
      );
      expect(number.controller!.text, isEmpty);
      final numberInput = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('client-number')),
          matching: find.byType(TextField),
        ),
      );
      expect(numberInput.focusNode!.hasFocus, isTrue);
      expect(
        find.text('Record saved. Enter the next client.').hitTestable(),
        findsOneWidget,
      );
      for (final disease in ['HIV', 'HCV', 'HBV', 'Syphilis']) {
        expect(
          tester
              .state<FormFieldState<String>>(
                find.byKey(ValueKey('test-$disease')),
              )
              .value,
          'No',
        );
      }
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('quantity-dist_3cc')),
            )
            .controller!
            .text,
        '0',
      );
      await tester.enterText(find.byKey(const ValueKey('client-number')), '46');
      await tap(tester, save);
      final records = await tester.runAsync(repo.encounters);
      final first = records!.firstWhere(
        (r) => r['client_code'].toString().endsWith('/0045'),
      );
      final second = records.firstWhere(
        (r) => r['client_code'].toString().endsWith('/0046'),
      );
      expect(first['hiv'], 'Reactive');
      expect(first['dist_3cc'], 7);
      expect(second['hiv'], 'No');
      expect(second['dist_3cc'], 0);
      expect(second['client_kind'], isNull);
      expect(await tester.runAsync(repo.pendingOperations), hasLength(4));
      await finish(tester);
    },
  );

  testWidgets(
    'failed duplicate save retains form values and shows feedback beside Save',
    (tester) async {
      await start(tester);
      await tester.enterText(find.byKey(const ValueKey('client-number')), '45');
      await tap(tester, save);
      await tester.enterText(find.byKey(const ValueKey('client-number')), '45');
      await tester.enterText(
        find.byKey(const ValueKey('quantity-dist_3cc')),
        '2',
      );
      await tester.enterText(
        find.byKey(const ValueKey('remark')),
        'Retain this',
      );
      await bottom(tester);
      await tap(tester, save);
      expect(
        find
            .text('This client already has a record for this hotspot today.')
            .hitTestable(),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('client-number')))
            .controller!
            .text,
        '45',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('quantity-dist_3cc')),
            )
            .controller!
            .text,
        '2',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('remark')))
            .controller!
            .text,
        'Retain this',
      );
      expect(scroll(tester).offset, greaterThan(0));
      expect(await tester.runAsync(repo.encounters), hasLength(1));
      expect(await tester.runAsync(repo.pendingOperations), hasLength(3));
      await finish(tester);
    },
  );
}
