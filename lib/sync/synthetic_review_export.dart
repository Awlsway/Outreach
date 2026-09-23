import 'package:flutter/services.dart';

/// Available only in an explicitly built synthetic test APK. No credentials.
class SyntheticReviewExport {
  static const enabled = bool.fromEnvironment('OUTREACH_SYNTHETIC_SYNC_TEST');
  static const _channel = MethodChannel('org.ansvk.outreach/synthetic_review');

  static Future<void> write(String exactBody) async {
    if (!enabled) throw StateError('Synthetic review export is disabled');
    await _channel.invokeMethod<String>('export', {'body': exactBody});
  }

  static Future<void> clear() async {
    if (!enabled) return;
    try {
      await _channel.invokeMethod<void>('clear');
    } catch (_) {
      // No payloads or platform exception details enter worker UI/logs.
    }
  }
}
