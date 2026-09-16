class PairingRequestBuilder {
  const PairingRequestBuilder({
    required this.appVersion,
    required this.clock,
  });

  final String appVersion;
  final DateTime Function() clock;

  Map<String, Object> build({
    required Map<String, Object?> appIdentity,
    required Map<String, Object?> worker,
    required String pairingCode,
  }) {
    final code = pairingCode.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw ArgumentError('Pairing code must be exactly 6 digits.');
    }
    final projectId = _requiredString(appIdentity, 'project_id');
    final projectName = _requiredString(appIdentity, 'project_name');
    final deviceId = _requiredString(appIdentity, 'device_id');
    final deviceCreatedAt = _requiredString(appIdentity, 'created_at');
    final workerId = _requiredString(worker, 'worker_id');
    final username = _requiredString(worker, 'username');

    return {
      'api_version': 1,
      'protocol': 'ansvk-outreach-sync',
      'protocol_version': 1,
      'project_id': projectId,
      'project_name': projectName,
      'schema_version': 6,
      'app_version': appVersion,
      'device_id': deviceId,
      'device_created_at': deviceCreatedAt,
      'worker_id': workerId,
      'username': username,
      'pairing_code': code,
      'requested_at': _utcSecond(clock()),
    };
  }

  static String _utcSecond(DateTime time) {
    final utc = time.toUtc();
    final year = utc.year.toString().padLeft(4, '0');
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    final hour = utc.hour.toString().padLeft(2, '0');
    final minute = utc.minute.toString().padLeft(2, '0');
    final second = utc.second.toString().padLeft(2, '0');
    return '$year-$month-${day}T$hour:$minute:${second}Z';
  }

  static String _requiredString(Map<String, Object?> row, String key) {
    final value = row[key]?.toString().trim() ?? '';
    if (value.isEmpty) throw ArgumentError('$key is required.');
    return value;
  }
}
