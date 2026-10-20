import 'dart:convert';
import 'package:sqflite_common/sqlite_api.dart';

typedef RetentionRow = Map<String, Object?>;

class RetentionCandidates {
  const RetentionCandidates(this.eligible, this.held);
  final List<RetentionRow> eligible;
  final int held;
}

/// Proof is conservative: every revision, exact latest state, and destination.
Future<RetentionCandidates> retentionCandidates(
  DatabaseExecutor tx, {
  required String owner,
  required String cutoff,
  required RetentionRow identity,
  required RetentionRow dashboard,
}) async {
  final old = await tx.query(
    'encounters',
    where: 'owner_id = ? AND visit_date < ?',
    whereArgs: [owner, cutoff],
  );
  final eligible = <RetentionRow>[];
  for (final encounter in old) {
    final operations = await tx.rawQuery(
      '''SELECT a.*, o.acknowledged_at,
      c.worker_id AS confirmed_worker, c.entity_id AS confirmed_entity,
      c.revision AS confirmed_revision, c.sequence AS confirmed_sequence,
      c.project_id, c.device_id, c.dashboard_id, c.accepted_at
      FROM audit_operations a
      LEFT JOIN sync_outbox o USING(operation_id)
      LEFT JOIN sync_confirmations c USING(operation_id)
      WHERE a.entity_type = 'encounter' AND a.entity_id = ? ORDER BY a.revision''',
      [encounter['encounter_id']],
    );
    var proven =
        dashboard['status'] == 'Paired' &&
        dashboard['dashboard_id'] is String &&
        operations.length == encounter['revision'] &&
        operations.isNotEmpty;
    for (var i = 0; proven && i < operations.length; i++) {
      final op = operations[i];
      final ack = op['acknowledged_at'];
      final stamp = ack is String ? DateTime.tryParse(ack) : null;
      proven =
          op['revision'] == i + 1 &&
          op['actor_id'] == owner &&
          op['confirmed_worker'] == owner &&
          op['confirmed_entity'] == encounter['encounter_id'] &&
          op['confirmed_revision'] == op['revision'] &&
          op['confirmed_sequence'] == op['sequence'] &&
          stamp != null &&
          stamp.isUtc &&
          op['accepted_at'] == ack &&
          op['project_id'] == identity['project_id'] &&
          op['device_id'] == identity['device_id'] &&
          op['dashboard_id'] == dashboard['dashboard_id'];
    }
    if (proven) {
      try {
        final latest = operations.last;
        final payload =
            jsonDecode(latest['payload'] as String) as Map<String, dynamic>;
        final state = latest['action'] == 'create'
            ? payload
            : payload['after'] as Map<String, dynamic>;
        proven =
            state.length == encounter.length &&
            encounter.keys.every((k) => state[k] == encounter[k]);
      } catch (_) {
        proven = false;
      }
    }
    if (proven) eligible.add(encounter);
  }
  return RetentionCandidates(eligible, old.length - eligible.length);
}

class RetentionCleanupResult {
  const RetentionCleanupResult({
    required this.eligible,
    required this.held,
    required this.removed,
  });
  final int eligible, held, removed;
}
