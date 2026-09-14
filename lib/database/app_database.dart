import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import 'database_key_store.dart';
import 'schema.dart';

class AppDatabase {
  AppDatabase._(this.connection);

  static const schemaVersion = 4;
  static const filename = 'ansvk_outreach.db';

  /// Infrastructure access only. Screens should use worker-scoped repositories.
  final Database connection;

  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? path,
    DatabaseKeyStore? keyStore,
  }) async {
    if (factory != null) {
      final dbPath = path ?? p.join(await factory.getDatabasesPath(), filename);
      final db = await factory.openDatabase(
        dbPath,
        options: _openOptions(),
      );
      return AppDatabase._(db);
    }

    final dbPath =
        path ?? p.join(await sqlcipher.getDatabasesPath(), filename);
    final passphrase = await (keyStore ?? DatabaseKeyStore()).readOrCreate();
    final db = await _openEncryptedWithMigration(dbPath, passphrase);
    return AppDatabase._(db);
  }

  static OpenDatabaseOptions _openOptions() {
    return OpenDatabaseOptions(
      version: schemaVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) => migrate(db, 0, version),
      onUpgrade: migrate,
      // Default downgrade handling rejects newer schemas; never delete data.
    );
  }

  static Future<Database> _openEncryptedWithMigration(
    String dbPath,
    String passphrase,
  ) async {
    try {
      return await _openEncrypted(dbPath, passphrase);
    } catch (_) {
      if (!await sqlcipher.databaseExists(dbPath)) rethrow;
      final migrated = await _tryMigratePlaintextDevelopmentDatabase(
        dbPath,
        passphrase,
      );
      if (!migrated) rethrow;
      return _openEncrypted(dbPath, passphrase);
    }
  }

  static Future<Database> _openEncrypted(String dbPath, String passphrase) {
    return sqlcipher.openDatabase(
      dbPath,
      version: schemaVersion,
      password: passphrase,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) => migrate(db, 0, version),
      onUpgrade: migrate,
      singleInstance: false,
    );
  }

  static Future<bool> _tryMigratePlaintextDevelopmentDatabase(
    String dbPath,
    String passphrase,
  ) async {
    final tempPath = '$dbPath.encrypted_migration';
    final backupPath = '$dbPath.plaintext_migration_backup';
    await _deleteDatabaseFiles(tempPath);
    await _deleteDatabaseFiles(backupPath);

    Database? plain;
    try {
      plain = await sqlcipher.openDatabase(
        dbPath,
        readOnly: false,
        singleInstance: false,
      );
      await plain.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' LIMIT 1",
      );
      await plain.execute(
        'ATTACH DATABASE ? AS encrypted KEY ?',
        [tempPath, passphrase],
      );
      await plain.rawQuery("SELECT sqlcipher_export('encrypted')");
      await plain.execute('PRAGMA encrypted.user_version = $schemaVersion');
      await plain.execute('DETACH DATABASE encrypted');
    } catch (_) {
      try {
        await plain?.execute('DETACH DATABASE encrypted');
      } catch (_) {
        // The database may not have been attached yet.
      }
      await plain?.close();
      await _deleteDatabaseFiles(tempPath);
      await _deleteDatabaseFiles(backupPath);
      return false;
    }
    await plain.close();

    final encrypted = await _openEncrypted(tempPath, passphrase);
    try {
      final result = await encrypted.rawQuery('PRAGMA integrity_check');
      if (result.isEmpty || result.first.values.first != 'ok') return false;
    } finally {
      await encrypted.close();
    }

    await _copyDatabaseFiles(dbPath, backupPath);
    await _deleteDatabaseFiles(dbPath);
    await _moveDatabaseFiles(tempPath, dbPath);
    await _deleteDatabaseFiles(backupPath);
    return true;
  }

  Future<void> close() => connection.close();

  static Future<void> _copyDatabaseFiles(String fromBase, String toBase) async {
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final from = File('$fromBase$suffix');
      if (await from.exists()) {
        await from.copy('$toBase$suffix');
      }
    }
  }

  static Future<void> _moveDatabaseFiles(String fromBase, String toBase) async {
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final from = File('$fromBase$suffix');
      if (await from.exists()) {
        await from.rename('$toBase$suffix');
      }
    }
  }

  static Future<void> _deleteDatabaseFiles(String basePath) async {
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final file = File('$basePath$suffix');
      if (await file.exists()) await file.delete();
    }
  }
}
