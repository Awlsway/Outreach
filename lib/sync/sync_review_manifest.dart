import 'dart:convert';
import 'dashboard_certificate_checker.dart';
import 'sync_batch_builder.dart';

/// Local metadata only. This never classifies a payload as synthetic or sends it.
class SyncReviewManifest {
  SyncReviewManifest._(
    this.batchId,
    this.projectId,
    this.workerId,
    this.deviceId,
    this.bodyHash,
    this.byteLength,
    List<SyncReviewOperation> operations,
  ) : operations = List.unmodifiable(operations);
  final String batchId, projectId, workerId, deviceId, bodyHash;
  final int byteLength;
  final List<SyncReviewOperation> operations;

  static Future<SyncReviewManifest> fromBatch(PreparedSyncBatch batch) async {
    final row = jsonDecode(batch.jsonBody) as Map<String, dynamic>;
    final entries = <SyncReviewOperation>[];
    final earlierCreates = <String>{};
    final earlierRevisions = <String>{};
    for (final op in row['operations'] as List) {
      final payload = op['payload'] as Map<String, dynamic>;
      final snapshot = payload['after'] is Map
          ? payload['after'] as Map
          : payload;
      final type = op['entity_type'] as String;
      final entityId = op['entity_id'] as String;
      final revision = op['revision'] as int;
      final dependencies = <String>[];
      if (type != 'worker' &&
          !earlierCreates.contains('worker:${row['worker_id']}')) {
        dependencies.add('Worker parent needs dashboard confirmation');
      }
      if (type == 'encounter' &&
          !earlierCreates.contains('hotspot:${snapshot['hotspot_id']}')) {
        dependencies.add('Hotspot parent needs dashboard confirmation');
      }
      if (revision > 1 &&
          !earlierRevisions.contains('$type:$entityId:${revision - 1}')) {
        dependencies.add('Previous revision needs dashboard confirmation');
      }
      entries.add(
        SyncReviewOperation(
          operationId: op['operation_id'] as String,
          entityType: type,
          entityId: entityId,
          action: op['action'] as String,
          revision: revision,
          sequence: op['sequence'] as int,
          label:
              (snapshot[type == 'encounter'
                      ? 'client_code'
                      : type == 'hotspot'
                      ? 'name'
                      : 'username']
                  as String?) ??
              'Record',
          payloadHash: await DashboardCertificateChecker.sha256Hex(
            utf8.encode(jsonEncode(payload)),
          ),
          dependencies: dependencies,
        ),
      );
      if (op['action'] == 'create') earlierCreates.add('$type:$entityId');
      earlierRevisions.add('$type:$entityId:$revision');
    }
    return SyncReviewManifest._(
      row['batch_id'] as String,
      row['project_id'] as String,
      row['worker_id'] as String,
      row['device_id'] as String,
      await DashboardCertificateChecker.sha256Hex(utf8.encode(batch.jsonBody)),
      batch.byteLength,
      entries,
    );
  }
}

class SyncReviewOperation {
  SyncReviewOperation({
    required this.operationId,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.label,
    required this.revision,
    required this.sequence,
    required this.payloadHash,
    required List<String> dependencies,
  }) : dependencies = List.unmodifiable(dependencies);
  final String operationId, entityType, entityId, action, label, payloadHash;
  final int revision, sequence;
  final List<String> dependencies;
}
