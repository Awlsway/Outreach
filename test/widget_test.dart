import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ansvk_outreach/app.dart';
import 'package:ansvk_outreach/auth/auth_service.dart';
import 'package:ansvk_outreach/auth/session_controller.dart';
import 'package:ansvk_outreach/database/app_database.dart';
import 'auth_test_support.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  late SessionController session;
  setUp(() async {
    db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    session = SessionController(AuthService(db, hasher: TestHasher()));
  });
  tearDown(() async {
    session.dispose();
    await db.close();
  });

  testWidgets(
    'registration and sign-in eye buttons preserve text and toggle independently',
    (tester) async {
      await tester.pumpWidget(
        OutreachApp(session: session, hasAccounts: false),
      );
      TextField field(String key) => tester.widget<TextField>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(TextField),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('password')),
        'My-password1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('confirm')),
        'My-password2',
      );
      expect(field('password').obscureText, isTrue);
      expect(field('confirm').obscureText, isTrue);
      Future<void> toggle(String key) async {
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pump();
      }

      await toggle('toggle-password');
      expect(field('password').obscureText, isFalse);
      expect(field('confirm').obscureText, isTrue);
      expect(field('password').controller!.text, 'My-password1');
      await toggle('toggle-confirm');
      expect(field('confirm').obscureText, isFalse);
      expect(field('confirm').controller!.text, 'My-password2');
      await toggle('toggle-password');
      expect(field('password').obscureText, isTrue);
      expect(field('confirm').obscureText, isFalse);
      final signIn = find.text('Already have an account? Sign in');
      await tester.ensureVisible(signIn);
      await tester.tap(signIn);
      await tester.pumpAndSettle();
      expect(field('password').obscureText, isTrue);
      expect(find.byKey(const ValueKey('confirm')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('password')),
        'Sign-in-password',
      );
      await toggle('toggle-password');
      expect(field('password').obscureText, isFalse);
      expect(field('password').controller!.text, 'Sign-in-password');
      await toggle('toggle-password');
      expect(field('password').obscureText, isTrue);
      expect(field('password').controller!.text, 'Sign-in-password');
    },
  );

  testWidgets(
    'register, logout, incorrect login and correct login through forms',
    (tester) async {
      await tester.pumpWidget(
        OutreachApp(session: session, hasAccounts: false),
      );
      await tester.enterText(find.byKey(const ValueKey('username')), 'Alice');
      await tester.enterText(
        find.byKey(const ValueKey('password')),
        'password1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('confirm')),
        'password1',
      );
      Future<void> submit() async {
        await tester.ensureVisible(find.byKey(const ValueKey('submit')));
        await tester.runAsync(() async {
          await tester.tap(find.byKey(const ValueKey('submit')));
          final deadline = DateTime.now().add(const Duration(seconds: 10));
          while (session.busy && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          expect(session.busy, isFalse);
        });
        await tester.pumpAndSettle();
      }

      await submit();
      expect(find.text('Signed in as Alice'), findsOneWidget);
      await tester.tap(find.byTooltip('Sign out'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('confirm')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('username')), 'Alice');
      await tester.enterText(
        find.byKey(const ValueKey('password')),
        'incorrect',
      );
      await submit();
      expect(find.text('Username or password is incorrect.'), findsOneWidget);
      expect(session.worker, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('password')),
        'password1',
      );
      await submit();
      expect(find.text('Signed in as Alice'), findsOneWidget);
    },
  );

  testWidgets(
    'password recovery warning appears on register and sign-in only',
    (tester) async {
      const warning =
          'Remember your password. Password recovery is not available '
          'in this pilot, and unsynced records may be lost if you cannot '
          'sign in.';
      await tester.pumpWidget(
        OutreachApp(session: session, hasAccounts: false),
      );
      expect(find.text(warning), findsOneWidget);
      final signIn = find.text('Already have an account? Sign in');
      await tester.ensureVisible(signIn);
      await tester.tap(signIn);
      await tester.pumpAndSettle();
      expect(find.text(warning), findsOneWidget);
      await tester.runAsync(
        () => session.signIn('Alice', 'password1', register: true),
      );
      await tester.pumpWidget(OutreachApp(session: session, hasAccounts: true));
      session.lock();
      await tester.pump();
      expect(find.text('App locked'), findsOneWidget);
      expect(find.text(warning), findsNothing);
    },
  );

  testWidgets('first-use registration form validates confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(OutreachApp(session: session, hasAccounts: false));
    expect(find.text('Create your account'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('username')), 'Alice');
    await tester.enterText(find.byKey(const ValueKey('password')), 'password1');
    await tester.enterText(find.byKey(const ValueKey('confirm')), 'different');
    await tester.ensureVisible(find.byKey(const ValueKey('submit')));
    await tester.tap(find.byKey(const ValueKey('submit')));
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(session.worker, isNull);
  });

  testWidgets(
    'one minute locks, activity resets timer and locked content is inaccessible',
    (tester) async {
      await tester.runAsync(
        () => session.signIn('Alice', 'password1', register: true),
      );
      await tester.pumpWidget(OutreachApp(session: session, hasAccounts: true));
      session.activity();
      await tester.pump(const Duration(seconds: 59));
      expect(find.text('You are signed in'), findsOneWidget);
      session.activity();
      await tester.pump(const Duration(seconds: 59));
      expect(session.locked, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('App locked'), findsOneWidget);
      expect(find.text('You are signed in'), findsNothing);
      expect(session.currentWorkerId, isNull);
      await tester.runAsync(() => session.unlock('password1'));
      await tester.pump();
      expect(find.text('You are signed in'), findsOneWidget);
      await tester.tap(find.byTooltip('Sign out'));
      await tester.pump();
      expect(find.byKey(const ValueKey('username')), findsOneWidget);
      expect(session.worker, isNull);
    },
  );
}
