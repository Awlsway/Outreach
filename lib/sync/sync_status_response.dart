/// Status is informational and never authorizes outbox acknowledgement/cleanup.
class SyncStatusResponse {
  SyncStatusResponse._(
    this.deviceId,
    this.workerId,
    this.serverTime,
    this.lastSuccessfulSyncAt,
    this.lastAcceptedSequence,
    this.lastAcceptedOperationId,
  );
  final String deviceId;
  final String workerId;
  final DateTime serverTime;
  final DateTime? lastSuccessfulSyncAt;
  final int? lastAcceptedSequence;
  final String? lastAcceptedOperationId;

  factory SyncStatusResponse.parse(
    Map<String, Object?> row, {
    required int httpStatus,
    required String expectedDeviceId,
    required String expectedWorkerId,
  }) {
    if (httpStatus != 200 ||
        row['ok'] != true ||
        expectedDeviceId.isEmpty ||
        expectedWorkerId.isEmpty ||
        row['device_id'] != expectedDeviceId ||
        row['worker_id'] != expectedWorkerId ||
        row['device_status'] != 'active' ||
        row['cleanup_keep_days'] != 7 ||
        row['cleanup_keep_days'] is! int ||
        row['request_id'] is! String ||
        (row['request_id'] as String).trim().isEmpty) {
      throw const FormatException('Invalid dashboard status or identity');
    }
    DateTime date(Object? value) {
      final parsed = value is String ? DateTime.tryParse(value) : null;
      if (parsed == null || !parsed.isUtc) {
        throw const FormatException('Invalid dashboard status time');
      }
      return parsed;
    }

    for (final field in [
      'last_successful_sync_at',
      'last_accepted_sequence',
      'last_accepted_operation_id',
    ]) {
      if (!row.containsKey(field)) {
        throw const FormatException('Missing status field');
      }
    }
    final sequence = row['last_accepted_sequence'];
    final operation = row['last_accepted_operation_id'];
    if ((sequence != null && (sequence is! int || sequence < 0)) ||
        (operation != null &&
            (operation is! String || operation.trim().isEmpty)) ||
        ((sequence == null) != (operation == null))) {
      throw const FormatException('Invalid dashboard status watermark');
    }
    final warnings = row['warnings'];
    if (warnings is! List) {
      throw const FormatException('Invalid status warnings');
    }
    for (final warning in warnings) {
      if (warning is! Map ||
          warning['code'] is! String ||
          warning['message'] is! String ||
          (warning['code'] as String).trim().isEmpty ||
          (warning['message'] as String).trim().isEmpty) {
        throw const FormatException('Invalid status warning');
      }
    }
    return SyncStatusResponse._(
      expectedDeviceId,
      expectedWorkerId,
      date(row['server_time']),
      row['last_successful_sync_at'] == null
          ? null
          : date(row['last_successful_sync_at']),
      sequence as int?,
      operation as String?,
    );
  }
}
