import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Read the installed Android version, including command-line build overrides.
class AppBuildVersion {
  static const channel = MethodChannel('org.ansvk.outreach/app_version');

  static Future<String> read() async {
    try {
      final value = await channel.invokeMethod<String>('read');
      if (value == null || !RegExp(r'^\d+\.\d+\.\d+\+\d+$').hasMatch(value)) {
        throw const FormatException('Invalid installed app version');
      }
      return value;
    } on MissingPluginException {
      if (kDebugMode) return 'development';
      rethrow;
    }
  }
}
