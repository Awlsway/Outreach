sealed class PairingResponseResult {
  const PairingResponseResult();

  factory PairingResponseResult.parse(
    Map<String, Object?> json, {
    required String expectedDeviceId,
    required String expectedWorkerId,
  }) {
    final ok = json['ok'];
    if (ok == true) {
      return PairingSuccess.fromJson(
        json,
        expectedDeviceId: expectedDeviceId,
        expectedWorkerId: expectedWorkerId,
      );
    }
    if (ok == false) return PairingFailure.fromJson(json);
    throw const FormatException('Pairing response must include ok true or false.');
  }
}

class PairingSuccess extends PairingResponseResult {
  const PairingSuccess({
    required this.requestId,
    required this.dashboardId,
    required this.dashboardName,
    required this.deviceId,
    required this.workerId,
    required this.deviceCredential,
    required this.pairedAt,
    required this.serverTime,
  });

  factory PairingSuccess.fromJson(
    Map<String, Object?> json, {
    required String expectedDeviceId,
    required String expectedWorkerId,
  }) {
    final deviceId = _requiredString(json, 'device_id');
    final workerId = _requiredString(json, 'worker_id');
    if (deviceId != expectedDeviceId) {
      throw const FormatException('Paired device did not match this phone.');
    }
    if (workerId != expectedWorkerId) {
      throw const FormatException('Paired worker did not match this account.');
    }
    final credential = _requiredString(json, 'device_credential');
    if (credential.length < 32) {
      throw const FormatException('Device credential is too short.');
    }
    return PairingSuccess(
      requestId: _requiredString(json, 'request_id'),
      dashboardId: _requiredString(json, 'dashboard_id'),
      dashboardName: _requiredString(json, 'dashboard_name'),
      deviceId: deviceId,
      workerId: workerId,
      deviceCredential: credential,
      pairedAt: _requiredDate(json, 'paired_at'),
      serverTime: _requiredDate(json, 'server_time'),
    );
  }

  final String requestId;
  final String dashboardId;
  final String dashboardName;
  final String deviceId;
  final String workerId;
  final String deviceCredential;
  final DateTime pairedAt;
  final DateTime serverTime;
}

class PairingFailure extends PairingResponseResult {
  const PairingFailure({
    required this.requestId,
    required this.errorCode,
    required this.message,
    required this.retryable,
  });

  factory PairingFailure.fromJson(Map<String, Object?> json) => PairingFailure(
    requestId: _requiredString(json, 'request_id'),
    errorCode: _requiredString(json, 'error_code'),
    message: _requiredString(json, 'message'),
    retryable: json['retryable'] == true,
  );

  final String requestId;
  final String errorCode;
  final String message;
  final bool retryable;

  String get workerMessage => switch (errorCode) {
    'invalid_pairing_code' => 'Pairing code was not accepted. Check the code and try again.',
    'expired_pairing_code' => 'Pairing code has expired. Ask the data assistant for a new code.',
    'pairing_attempts_exhausted' => 'Pairing code is blocked. Ask the data assistant for a new code.',
    'pairing_code_used' => 'Pairing code has already been used. Ask the data assistant for a new code.',
    'pairing_code_cancelled' => 'Pairing code was cancelled. Ask the data assistant for a new code.',
    'worker_has_active_device' => 'This worker already has an active phone. Ask staff to replace it first.',
    _ => message,
  };
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key]?.toString().trim() ?? '';
  if (value.isEmpty) throw FormatException('$key is required.');
  return value;
}

DateTime _requiredDate(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('$key is not a valid date.');
  return parsed.toUtc();
}
