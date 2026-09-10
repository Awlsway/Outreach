import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'schema.dart';

class AppDatabase {
  AppDatabase._(this.connection);

  static const schemaVersion = 2;
  static const filename = 'ansvk_outreach.db';

  /// Infrastructure access only. Screens should use worker-scoped repositories.
  final Database connection;

  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final backend = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await backend.getDatabasesPath(), filename);
    final db = await backend.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => migrate(db, 0, version),
        onUpgrade: migrate,
        // Default downgrade handling rejects newer schemas; never delete data.
      ),
    );
    return AppDatabase._(db);
  }

  Future<void> close() => connection.close();
}
