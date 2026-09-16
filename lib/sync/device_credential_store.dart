import 'dart:io' show Platform;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceCredentialStore {
  DeviceCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage,
      _memory = storage == null && !Platform.isAndroid;

  static const _key = 'ansvk_outreach_dashboard_device_credential';
  static const _defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      migrateWithBackup: false,
      storageNamespace: 'ansvk_outreach_dashboard_device',
    ),
  );

  final FlutterSecureStorage? _storage;
  final bool _memory;
  String? _memoryValue;

  FlutterSecureStorage get _effectiveStorage => _storage ?? _defaultStorage;

  Future<void> write(String credential) async {
    final value = credential.trim();
    if (value.isEmpty) throw ArgumentError('Device credential is required.');
    if (_memory) {
      _memoryValue = value;
      return;
    }
    await _effectiveStorage.write(key: _key, value: value);
  }

  Future<String?> read() async {
    if (_memory) return _memoryValue;
    final value = await _effectiveStorage.read(key: _key);
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  Future<void> clear() async {
    if (_memory) {
      _memoryValue = null;
      return;
    }
    await _effectiveStorage.delete(key: _key);
  }
}
