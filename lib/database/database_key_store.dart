import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DatabaseKeyStore {
  DatabaseKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? _defaultStorage;

  static const _key = 'ansvk_outreach_database_passphrase';
  static const _defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      migrateWithBackup: true,
      storageNamespace: 'ansvk_outreach_database_key',
    ),
  );

  final FlutterSecureStorage _storage;

  Future<String> readOrCreate() async {
    final existing = await _storage.read(key: _key);
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = _generatePassphrase();
    await _storage.write(key: _key, value: generated);
    return generated;
  }

  String _generatePassphrase() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }
}
