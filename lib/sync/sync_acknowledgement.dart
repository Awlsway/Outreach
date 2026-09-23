import 'dart:convert';

import 'sync_batch_builder.dart';

/// Validates offline receipts. This type cannot change the database/outbox.
class SyncAcknowledgement {
  SyncAcknowledgement._({
    required this.batchId,
    required this.requestId,
    required this.receivedAt,
    required List<AcceptedSyncOperation> accepted,
    required List<RejectedSyncOperation> rejected,
    required List<String> missing,
    required List<SyncReceiptWarning> warnings,
    required this.retryAfterSeconds,
  }) : accepted = List.unmodifiable(accepted),
       rejected = List.unmodifiable(rejected),
       missingOperationIds = List.unmodifiable(missing),
       warnings = List.unmodifiable(warnings);

  final String batchId;
  final String requestId;
  final DateTime receivedAt;
  final List<AcceptedSyncOperation> accepted;
  final List<RejectedSyncOperation> rejected;
  final List<String> missingOperationIds;
  final List<SyncReceiptWarning> warnings;
  final int? retryAfterSeconds;
  bool get allAccepted => rejected.isEmpty && missingOperationIds.isEmpty;

  factory SyncAcknowledgement.parse(
    Map<String, Object?> response, {
    required PreparedSyncBatch sentBatch,
    required int httpStatus,
  }) {
    if (httpStatus != 200 || response['ok'] != true) {
      throw const FormatException('Response is not a processed batch receipt.');
    }
    final sent = jsonDecode(sentBatch.jsonBody);
    if (sent is! Map<String, dynamic> ||
        sent['operations'] is! List ||
        (sent['operations'] as List).isEmpty) {
      throw const FormatException('A nonempty sent batch is required.');
    }
    final batchId = _string(response, 'batch_id');
    if (batchId != sent['batch_id']) {
      throw const FormatException('Receipt belongs to another batch.');
    }
    final requestId = _string(response, 'request_id');
    final receivedAt = _date(response, 'dashboard_received_at');
    final operations = <String, Map<String, dynamic>>{};
    for (final item in sent['operations'] as List) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid sent operation.');
      }
      final id = _string(item, 'operation_id');
      if (operations.containsKey(id)) {
        throw const FormatException('Duplicate sent operation.');
      }
      operations[id] = item;
    }
    final seen = <String>{};
    Map<String, dynamic> matched(dynamic value) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid receipt entry.');
      }
      final id = _string(value, 'operation_id');
      final expected = operations[id];
      if (expected == null || !seen.add(id)) {
        throw const FormatException('Unknown or repeated receipt operation.');
      }
      for (final field in [
        'entity_type',
        'entity_id',
        'revision',
        'sequence',
      ]) {
        if (value[field] != expected[field] ||
            (['revision', 'sequence'].contains(field) &&
                value[field] is! int)) {
          throw const FormatException(
            'Receipt identity does not match the sent operation.',
          );
        }
      }
      return value;
    }

    final accepted = <AcceptedSyncOperation>[];
    for (final item in _list(response, 'accepted')) {
      final row = matched(item);
      if (row['duplicate'] is! bool) {
        throw const FormatException('Invalid duplicate indicator.');
      }
      accepted.add(
        AcceptedSyncOperation._(
          row,
          _date(row, 'accepted_at'),
          row['duplicate'] as bool,
        ),
      );
    }
    final rejected = <RejectedSyncOperation>[];
    for (final item in _list(response, 'rejected')) {
      final row = matched(item);
      if (row['retryable'] is! bool) {
        throw const FormatException('Invalid retryable indicator.');
      }
      rejected.add(
        RejectedSyncOperation._(
          row,
          _string(row, 'error_code'),
          row['retryable'] as bool,
          _string(row, 'message'),
        ),
      );
    }
    final warnings = <SyncReceiptWarning>[];
    for (final item in _list(response, 'warnings')) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid receipt warning.');
      }
      warnings.add(
        SyncReceiptWarning(_string(item, 'code'), _string(item, 'message')),
      );
    }
    if (!response.containsKey('retry_after_seconds')) {
      throw const FormatException('Missing retry delay.');
    }
    final delay = response['retry_after_seconds'];
    if (delay != null && (delay is! int || delay < 0)) {
      throw const FormatException('Invalid retry delay.');
    }
    return SyncAcknowledgement._(
      batchId: batchId,
      requestId: requestId,
      receivedAt: receivedAt,
      accepted: accepted,
      rejected: rejected,
      missing: operations.keys.where((id) => !seen.contains(id)).toList(),
      warnings: warnings,
      retryAfterSeconds: delay as int?,
    );
  }
}

class SyncReceiptOperation {
  SyncReceiptOperation._(Map<String, dynamic> row)
    : operationId = row['operation_id'] as String,
      entityType = row['entity_type'] as String,
      entityId = row['entity_id'] as String,
      revision = row['revision'] as int,
      sequence = row['sequence'] as int;
  final String operationId;
  final String entityType;
  final String entityId;
  final int revision;
  final int sequence;
}

class AcceptedSyncOperation extends SyncReceiptOperation {
  AcceptedSyncOperation._(super.row, this.acceptedAt, this.duplicate)
    : super._();
  final DateTime acceptedAt;
  final bool duplicate;
}

class RejectedSyncOperation extends SyncReceiptOperation {
  RejectedSyncOperation._(
    super.row,
    this.errorCode,
    this.retryable,
    this.message,
  ) : super._();
  final String errorCode;
  final bool retryable;
  // Untrusted server text, for internal inspection only; never log client data.
  final String message;
}

class SyncReceiptWarning {
  const SyncReceiptWarning(this.code, this.message);
  final String code;
  final String message;
}

String _string(Map<String, dynamic> row, String field) {
  final value = row[field];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Missing receipt text field.');
  }
  return value;
}

DateTime _date(Map<String, dynamic> row, String field) {
  final value = DateTime.tryParse(_string(row, field));
  if (value == null || !value.isUtc) {
    throw const FormatException('Receipt timestamp must identify UTC time.');
  }
  return value;
}

List<dynamic> _list(Map<String, dynamic> row, String field) {
  final value = row[field];
  if (value is! List) throw const FormatException('Missing receipt list.');
  return value;
}
