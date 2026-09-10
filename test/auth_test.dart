import 'dart:io';

import 'package:ansvk_outreach/auth/auth_service.dart';
import 'package:ansvk_outreach/auth/password_hasher.dart';
import 'package:ansvk_outreach/auth/session_controller.dart';
import 'package:ansvk_outreach/database/app_database.dart';
import 'package:ansvk_outreach/database/outreach_repository.dart';
import 'package:ansvk_outreach/database/schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'auth_test_support.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  late AuthService auth;
  var now = DateTime(2026, 9, 10, 10);
  setUp(() async {
    db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    now = DateTime(2026, 9, 10, 10);
    auth = AuthService(db, hasher: TestHasher(), clock: () => now);
  });
  tearDown(() => db.close());

  test(
    'registration saves identity and credential atomically without auditing password material',
    () async {
      final worker = await auth.register(' Alice ', 'secret-pass');
      expect(worker.username, 'Alice');
      expect(await auth.hasAccounts(), isTrue);
      expect((await auth.authenticate('Alice', 'secret-pass')).id, worker.id);
      final audit = (await db.connection.query('audit_operations')).single;
      expect(audit['payload'].toString(), isNot(contains('secret-pass')));
      expect(audit['payload'].toString(), isNot(contains('verifier')));
      expect(audit['payload'].toString(), isNot(contains('salt')));
      await expectLater(
        auth.register('Alice', 'new-password'),
        throwsA(isA<AuthFailure>()),
      );
      expect(await db.connection.query('workers'), hasLength(1));
      expect(await db.connection.query('credentials'), hasLength(1));
      await db.connection.execute(
        '''CREATE TRIGGER fail_outbox BEFORE INSERT ON sync_outbox
      BEGIN SELECT RAISE(ABORT, 'failure'); END''',
      );
      await expectLater(
        auth.register('Bob', 'password2'),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.connection.query('workers'), hasLength(1));
      expect(await db.connection.query('credentials'), hasLength(1));
    },
  );

  test(
    'wrong password and unknown account fail; cooldown persists and expires',
    () async {
      await auth.register('Alice', 'correct-pass');
      await expectLater(
        auth.authenticate('missing', 'wrong'),
        throwsA(isA<AuthFailure>()),
      );
      for (var i = 0; i < 5; i++) {
        await expectLater(
          auth.authenticate('Alice', 'wrong'),
          throwsA(isA<AuthFailure>()),
        );
      }
      // A fresh service cannot bypass the stored cooldown.
      auth = AuthService(db, hasher: TestHasher(), clock: () => now);
      await expectLater(
        auth.authenticate('Alice', 'correct-pass'),
        throwsA(isA<AuthFailure>()),
      );
      now = now.add(const Duration(seconds: 31));
      expect(
        (await auth.authenticate('Alice', 'correct-pass')).username,
        'Alice',
      );
      expect(
        (await db.connection.query('credentials')).single['failed_attempts'],
        0,
      );
    },
  );

  test('registration validates fields before storing anything', () async {
    await expectLater(
      auth.register(' ', 'password'),
      throwsA(isA<AuthFailure>()),
    );
    await expectLater(
      auth.register('Alice', 'short'),
      throwsA(isA<AuthFailure>()),
    );
    expect(await auth.hasAccounts(), isFalse);
    expect(await db.connection.query('workers'), isEmpty);
  });

  test(
    'session lock blocks repositories, unlock requires same password, logout clears identity',
    () async {
      final session = SessionController(auth, clock: () => now);
      addTearDown(session.dispose);
      await session.signIn('Alice', 'password1', register: true);
      final id = session.currentWorkerId;
      final repo = OutreachRepository(
        db,
        currentWorkerId: () => session.currentWorkerId,
      );
      await repo.createHotspot(name: 'Alice only');
      session.lock();
      expect(session.currentWorkerId, isNull);
      expect(() => repo.encounters(), throwsStateError);
      await expectLater(session.unlock('wrong'), throwsA(isA<AuthFailure>()));
      expect(session.locked, isTrue);
      await session.unlock('password1');
      expect(session.currentWorkerId, id);
      expect(await repo.hotspots(), hasLength(1));
      session.logout();
      expect(session.worker, isNull);
      expect(session.currentWorkerId, isNull);
      await session.signIn('Bob', 'password2', register: true);
      expect(await repo.hotspots(), isEmpty);
    },
  );

  test('background concealment does not reset inactivity deadline', () async {
    final session = SessionController(auth, clock: () => now);
    addTearDown(session.dispose);
    await session.signIn('Alice', 'password1', register: true);
    session.setForeground(false);
    expect(session.currentWorkerId, isNull);
    now = now.add(const Duration(seconds: 59));
    session.setForeground(true);
    expect(session.locked, isFalse);
    session.setForeground(false);
    now = now.add(const Duration(seconds: 2));
    session.setForeground(true);
    expect(session.locked, isTrue);
    expect(session.currentWorkerId, isNull);
  });

  test(
    'version 1 migration preserves outreach records and restart requires login',
    () async {
      final dir = await Directory.systemTemp.createTemp('ansvk_upgrade_');
      final path = '${dir.path}/upgrade.db';
      try {
        final old = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) => migrate(db, 0, 1),
          ),
        );
        await old.insert('workers', {
          'worker_id': 'old-id',
          'username': 'Legacy',
          'created_at': '2026-09-10T00:00:00Z',
        });
        await old.insert('hotspots', {
          'hotspot_id': 'old-site',
          'owner_id': 'old-id',
          'name': 'Saved site',
          'created_at': '2026-09-10T00:00:00Z',
        });
        await old.close();
        var upgraded = await AppDatabase.open(
          factory: databaseFactoryFfi,
          path: path,
        );
        var service = AuthService(upgraded, hasher: TestHasher());
        final worker = await service.register('Alice', 'password1');
        expect(await upgraded.connection.getVersion(), 2);
        expect(
          (await upgraded.connection.query('hotspots')).single['name'],
          'Saved site',
        );
        await upgraded.close();
        upgraded = await AppDatabase.open(
          factory: databaseFactoryFfi,
          path: path,
        );
        service = AuthService(upgraded, hasher: TestHasher());
        final session = SessionController(service);
        expect(session.currentWorkerId, isNull);
        await session.signIn('Alice', 'password1');
        expect(session.currentWorkerId, worker.id);
        session.dispose();
        await upgraded.close();
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'production PBKDF2 uses random salts and validates only the correct password',
    () async {
      final hasher = Pbkdf2PasswordHasher();
      final first = await hasher.hash('sample-password');
      final second = await hasher.hash('sample-password');
      expect(first.iterations, 600000);
      expect(first.salt, isNot(second.salt));
      expect(first.verifier, isNot(second.verifier));
      expect(first.verifier, isNot(contains('sample-password')));
      expect(await hasher.verify('sample-password', first), isTrue);
      expect(await hasher.verify('wrong-password', first), isFalse);
    },
  );
}
