import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../database/schema.dart';

/// Offline preparation only: no transport, credentials or database writes.
class SyncBatchBuilder {
  SyncBatchBuilder({
    required this.appVersion,
    required this.clock,
    String Function()? newBatchId,
  }) : _newBatchId = newBatchId ?? const Uuid().v4;

  static const maxOperations = 100;
  static const maxBytes = 1024 * 1024;
  final String appVersion;
  final DateTime Function() clock;
  final String Function() _newBatchId;

  List<PreparedSyncBatch> build({
    required Map<String, Object?> appIdentity,
    required String workerId,
    required List<Map<String, Object?>> pendingOperations,
  }) {
    for (final field in [
      'project_id',
      'project_name',
      'device_id',
      'created_at',
    ]) {
      if (appIdentity[field] is! String ||
          (appIdentity[field] as String).trim().isEmpty) {
        throw FormatException('Missing app identity field: $field');
      }
    }
    if (workerId.isEmpty || appVersion.isEmpty) {
      throw const FormatException('Missing worker or app version.');
    }
    final rows = List<Map<String, Object?>>.of(pendingOperations);
    final ids = <String>{};
    final sequences = <int>{};
    final operations = <Map<String, Object?>>[];
    for (final row in rows) {
      final sequence = row['sequence'];
      final id = row['operation_id'];
      if (sequence is! int ||
          sequence < 1 ||
          !sequences.add(sequence) ||
          id is! String ||
          id.isEmpty ||
          !ids.add(id)) {
        throw const FormatException(
          'Invalid or duplicate pending operation identity.',
        );
      }
      if (row['actor_id'] != workerId) {
        throw const FormatException(
          'Pending operation belongs to another worker.',
        );
      }
      if (row['revision'] is! int ||
          (row['revision'] as int) < 1 ||
          row['entity_id'] is! String ||
          (row['entity_id'] as String).isEmpty) {
        throw const FormatException('Invalid entity identity or revision.');
      }
      if (row['occurred_at'] is! String ||
          DateTime.tryParse(row['occurred_at'] as String) == null) {
        throw const FormatException('Invalid operation timestamp.');
      }
      final decoded = row['payload'] is String
          ? jsonDecode(row['payload'] as String)
          : row['payload'];
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Operation payload must be a JSON object.');
      }
      _validatePayload(row, decoded, workerId);
      operations.add({
        for (final key in [
          'sequence',
          'operation_id',
          'actor_id',
          'entity_type',
          'entity_id',
          'revision',
          'action',
          'occurred_at',
        ])
          key: row[key],
        'payload': decoded,
      });
    }
    operations.sort(
      (a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int),
    );
    if (operations.isEmpty) return const [];
    final timestamp = clock().toUtc().toIso8601String().replaceFirst(
      '.000Z',
      'Z',
    );
    final batches = <PreparedSyncBatch>[];
    var batchId = _newBatchId();
    var current = <Map<String, Object?>>[];
    PreparedSyncBatch encode(List<Map<String, Object?>> items) =>
        PreparedSyncBatch(
          jsonEncode({
            'api_version': 1,
            'protocol': 'ansvk-outreach-sync',
            'protocol_version': 1,
            'project_id': appIdentity['project_id'],
            'project_name': appIdentity['project_name'],
            'schema_version': AppDatabase.schemaVersion,
            'app_version': appVersion,
            'batch_id': batchId,
            'device_id': appIdentity['device_id'],
            'device_created_at': appIdentity['created_at'],
            'worker_id': workerId,
            'batch_created_at': timestamp,
            'operations': items,
          }),
        );
    for (final operation in operations) {
      final candidate = [...current, operation];
      if (candidate.length > maxOperations ||
          encode(candidate).byteLength > maxBytes) {
        if (current.isNotEmpty) {
          batches.add(encode(current));
          batchId = _newBatchId();
          current = [];
        }
        if (encode([operation]).byteLength > maxBytes) {
          // Abort preparation rather than skipping a dependency/revision.
          throw const FormatException(
            'A pending operation exceeds the 1 MiB batch limit. All records remain pending.',
          );
        }
      }
      current.add(operation);
    }
    if (current.isNotEmpty) batches.add(encode(current));
    return List.unmodifiable(batches);
  }

  static void _validatePayload(
    Map<String, Object?> operation,
    Map<String, dynamic> payload,
    String worker,
  ) {
    final type = operation['entity_type'];
    final action = operation['action'];
    if (!['worker', 'hotspot', 'encounter'].contains(type) ||
        !['create', 'update', 'delete'].contains(action) ||
        (type != 'encounter' && action != 'create')) {
      throw const FormatException(
        'Unsupported pending operation type or action.',
      );
    }
    final encounterFields = <String>{
      'encounter_id',
      'owner_id',
      'hotspot_id',
      'client_code',
      'visit_date',
      'client_kind',
      ...newClientChoices.keys,
      ...testFields,
      ...quantityFields,
      'refer_dic',
      'remark',
      'created_at',
      'updated_at',
      'revision',
      'deleted_at',
    };
    void validateRow(Map<String, dynamic> row, int revision) {
      final fields = type == 'worker'
          ? <String>{'worker_id', 'username', 'created_at'}
          : type == 'hotspot'
          ? <String>{
              'hotspot_id',
              'owner_id',
              'name',
              'latitude',
              'longitude',
              'location_status',
              'created_at',
              'revision',
              'peers',
            }
          : encounterFields;
      if (row.keys.any((key) => !fields.contains(key))) {
        throw const FormatException(
          'Unexpected payload field; preparation blocked.',
        );
      }
      if (row['${type}_id'] != operation['entity_id'] ||
          (type == 'worker' ? row['worker_id'] : row['owner_id']) != worker) {
        throw const FormatException(
          'Payload identity does not match operation ownership.',
        );
      }
      if (type != 'worker' && row['revision'] != revision) {
        throw const FormatException(
          'Payload revision does not match operation.',
        );
      }
    }

    if (action == 'create') {
      validateRow(payload, operation['revision'] as int);
    } else {
      if (payload.length != 2 ||
          payload['before'] is! Map<String, dynamic> ||
          payload['after'] is! Map<String, dynamic>) {
        throw const FormatException(
          'Encounter change requires before and after snapshots.',
        );
      }
      validateRow(
        payload['before'] as Map<String, dynamic>,
        (operation['revision'] as int) - 1,
      );
      validateRow(
        payload['after'] as Map<String, dynamic>,
        operation['revision'] as int,
      );
    }
  }
}

/// Immutable JSON bytes for an eventual exact retry. Contains service data;
/// must not be logged or displayed in normal worker screens.
class PreparedSyncBatch {
  PreparedSyncBatch(this.jsonBody);
  final String jsonBody;
  int get byteLength => utf8.encode(jsonBody).length;
}
