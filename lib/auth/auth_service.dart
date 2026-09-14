import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'password_hasher.dart';

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
}

class WorkerIdentity {
  const WorkerIdentity(this.id, this.username);
  final String id;
  final String username;
}

class AuthService {
  AuthService(
    this.database, {
    PasswordHasher? hasher,
    DateTime Function()? clock,
  }) : _hasher = hasher ?? Pbkdf2PasswordHasher(),
       _clock = clock ?? DateTime.now;

  final AppDatabase database;
  final PasswordHasher _hasher;
  final DateTime Function() _clock;
  static const _uuid = Uuid();

  Future<bool> hasAccounts() async =>
      (await database.connection.query('credentials', limit: 1)).isNotEmpty;

  Future<WorkerIdentity> register(String username, String password) async {
    final name = username.trim();
    if (name.isEmpty || name.length > 64) {
      throw const AuthFailure('Enter a username of 1–64 characters.');
    }
    if (password.length < 8 || password.length > 128) {
      throw const AuthFailure('Use a password of 8–128 characters.');
    }
    final digest = await _hasher.hash(password);
    final id = _uuid.v4();
    final operation = _uuid.v4();
    final stamp = _clock().toUtc().toIso8601String();
    try {
      await database.connection.transaction((tx) async {
        final profile = {
          'worker_id': id,
          'username': name,
          'created_at': stamp,
        };
        await tx.insert('workers', profile);
        await tx.insert('credentials', {
          'worker_id': id,
          'algorithm': 'pbkdf2-sha256',
          'salt': digest.salt,
          'verifier': digest.verifier,
          'iterations': digest.iterations,
        });
        await tx.insert('sync_state', {'worker_id': id});
        await tx.insert('audit_operations', {
          'operation_id': operation, 'actor_id': id, 'entity_type': 'worker',
          'entity_id': id,
          'revision': 1,
          'action': 'create',
          'occurred_at': stamp,
          // Credentials never enter the audit history or synchronization queue.
          'payload': jsonEncode(profile),
        });
        await tx.insert('sync_outbox', {'operation_id': operation});
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const AuthFailure('That username already exists on this phone.');
      }
      rethrow;
    }
    return WorkerIdentity(id, name);
  }

  Future<WorkerIdentity> authenticate(String username, String password) async {
    if (password.length > 128) {
      throw const AuthFailure('Username or password is incorrect.');
    }
    final rows = await database.connection.rawQuery(
      '''
      SELECT w.username, c.* FROM workers w JOIN credentials c USING(worker_id)
      WHERE w.username = ?''',
      [username.trim()],
    );
    if (rows.isEmpty) {
      // Keep unknown accounts on the same password-work path.
      await _hasher.verify(
        password,
        PasswordDigest(
          base64Encode(List.filled(32, 0)),
          base64Encode(List.filled(32, 0)),
          600000,
        ),
      );
      throw const AuthFailure('Username or password is incorrect.');
    }
    final credential = rows.single;
    void checkCooldown(Map<String, Object?> row) {
      final blocked = row['blocked_until'] as String?;
      if (blocked != null &&
          _clock().toUtc().isBefore(DateTime.parse(blocked))) {
        throw const AuthFailure(
          'Too many attempts. Wait 30 seconds and try again.',
        );
      }
    }

    checkCooldown(credential);
    if (credential['algorithm'] != 'pbkdf2-sha256') {
      throw StateError('Unsupported credential format');
    }
    final valid = await _hasher.verify(
      password,
      PasswordDigest(
        credential['salt'] as String,
        credential['verifier'] as String,
        credential['iterations'] as int,
      ),
    );
    // Persist failed attempts even though the public call reports an error.
    await database.connection.transaction((tx) async {
      final latest = (await tx.query(
        'credentials',
        where: 'worker_id = ?',
        whereArgs: [credential['worker_id']],
      )).single;
      checkCooldown(latest);
      final failures = (latest['failed_attempts'] as int) + 1;
      await tx.update(
        'credentials',
        {
          'failed_attempts': valid || failures >= 5 ? 0 : failures,
          'blocked_until': !valid && failures >= 5
              ? _clock()
                    .toUtc()
                    .add(const Duration(seconds: 30))
                    .toIso8601String()
              : null,
        },
        where: 'worker_id = ?',
        whereArgs: [credential['worker_id']],
      );
    });
    if (!valid) throw const AuthFailure('Username or password is incorrect.');
    return WorkerIdentity(
      credential['worker_id'] as String,
      credential['username'] as String,
    );
  }
}
