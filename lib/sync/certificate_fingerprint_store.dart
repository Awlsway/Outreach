import 'dart:io' show Platform;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CertificateFingerprintStore {
  CertificateFingerprintStore({FlutterSecureStorage? storage})
    : _storage = storage,
      _memory = storage == null && !Platform.isAndroid;

  static const _key = 'ansvk_outreach_dashboard_certificate_sha256';
  static const _defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      migrateWithBackup: false,
      storageNamespace: 'ansvk_outreach_dashboard_trust',
    ),
  );

  final FlutterSecureStorage? _storage;
  final bool _memory;
  String? _memoryValue;

  FlutterSecureStorage get _effectiveStorage => _storage ?? _defaultStorage;

  Future<void> write(String fingerprint) async {
    final normalized = normalize(fingerprint);
    if (_memory) {
      _memoryValue = normalized;
      return;
    }
    await _effectiveStorage.write(key: _key, value: normalized);
  }

  Future<String?> read() async {
    if (_memory) return _memoryValue;
    final value = await _effectiveStorage.read(key: _key);
    if (value == null || value.isEmpty) return null;
    return normalize(value);
  }

  Future<void> clear() async {
    if (_memory) {
      _memoryValue = null;
      return;
    }
    await _effectiveStorage.delete(key: _key);
  }

  static String normalize(String value) =>
      value.replaceAll(RegExp(r'[\s:-]'), '').toUpperCase();

  static bool isValidSha256(String value) =>
      RegExp(r'^[0-9A-F]{64}$').hasMatch(normalize(value));

  static String hint(String normalized) =>
      normalized.length <= 16 ? normalized : '...${normalized.substring(48)}';
}
