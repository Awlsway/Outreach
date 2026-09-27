import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import 'app_database.dart';
import 'schema.dart';
import 'retention_cleanup.dart';
import '../sync/pairing_response.dart';
import '../sync/sync_acknowledgement.dart';
import '../sync/sync_batch_builder.dart';

typedef Row = Map<String, Object?>;

/// Local persistence only. The trusted authentication layer (not a form) must
/// provide currentWorkerId. SessionController supplies null while locked,
/// backgrounded, timed out or signed out.
class OutreachRepository {
  OutreachRepository(
    this.database, {
    required this.currentWorkerId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase database;
  final String? Function() currentWorkerId;
  final DateTime Function() _clock;
  static const _uuid = Uuid();
  Database get _db => database.connection;

  /// Device/project metadata that future sync batches will send to the
  /// dashboard before operation payloads.
  Future<Row> appIdentity() async =>
      (await _db.query('app_identity', limit: 1)).single;

  /// Signed-in worker metadata for future pairing requests. This intentionally
  /// reads only the worker profile, not password verifier material.
  Future<Row> currentWorkerProfile() async => (await _db.query(
    'workers',
    columns: ['worker_id', 'username', 'created_at'],
    where: 'worker_id = ?',
    whereArgs: [_owner],
    limit: 1,
  )).single;

  String get _owner {
    final value = currentWorkerId();
    if (value == null || value.isEmpty) throw StateError('No worker session');
    return value;
  }

  static String _day(DateTime time) =>
      '${time.year.toString().padLeft(4, '0')}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';

  static const _retentionKeepDays = 7;

  String _retentionCutoffDay() {
    final now = _clock();
    return _day(
      DateTime(now.year, now.month, now.day - (_retentionKeepDays - 1)),
    );
  }

  /// Profile-only infrastructure provisioning (also used by database tests).
  /// UI registration must use AuthService's atomic credential/profile creation.
  /// This method does not create a login or sign in the worker.
  Future<String> createWorkerProfile(String username) async {
    final id = _uuid.v4();
    final now = _clock().toUtc().toIso8601String();
    final row = {
      'worker_id': id,
      'username': username.trim(),
      'created_at': now,
    };
    await _db.transaction((tx) async {
      await tx.insert('workers', row);
      await tx.insert('sync_state', {'worker_id': id});
      await _audit(tx, id, 'worker', id, 1, 'create', now, row);
    });
    return id;
  }

  Future<void> _audit(
    Transaction tx,
    String owner,
    String type,
    String id,
    int revision,
    String action,
    String time,
    Row payload,
  ) async {
    final operation = _uuid.v4();
    await tx.insert('audit_operations', {
      'operation_id': operation,
      'actor_id': owner,
      'entity_type': type,
      'entity_id': id,
      'revision': revision,
      'action': action,
      'occurred_at': time,
      'payload': jsonEncode(payload),
    });
    await tx.insert('sync_outbox', {'operation_id': operation});
  }

  Future<String> createHotspot({
    required String name,
    List<String> peers = const [],
    double? latitude,
    double? longitude,
  }) async {
    final owner = _owner;
    final id = _uuid.v4();
    final now = _clock().toUtc().toIso8601String();
    final names = peers
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    final row = <String, Object?>{
      'hotspot_id': id,
      'owner_id': owner,
      'name': name.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'location_status': latitude == null && longitude == null
          ? 'Unavailable'
          : 'Available',
      'created_at': now,
      'revision': 1,
    };
    await _db.transaction((tx) async {
      await tx.insert('hotspots', row);
      for (var i = 0; i < names.length; i++) {
        await tx.insert('hotspot_peers', {
          'hotspot_id': id,
          'position': i,
          'name': names[i],
        });
      }
      await _audit(tx, owner, 'hotspot', id, 1, 'create', now, {
        ...row,
        'peers': names,
      });
    });
    return id;
  }

  Future<List<Row>> hotspots({String search = ''}) async {
    final owner = _owner;
    return _db.transaction((tx) async {
      final rows = await tx.query(
        'hotspots',
        where: 'owner_id = ? AND instr(lower(name), lower(?)) > 0',
        whereArgs: [owner, search.trim()],
        orderBy: 'name, hotspot_id',
      );
      final result = <Row>[];
      for (final row in rows) {
        final peers = await tx.query(
          'hotspot_peers',
          where: 'hotspot_id = ?',
          whereArgs: [row['hotspot_id']],
          orderBy: 'position',
        );
        result.add({...row, 'peers': peers.map((p) => p['name']).toList()});
      }
      return result;
    });
  }

  Row _input(Row input) {
    final allowed = {
      'hotspot_id',
      'client_code',
      'client_kind',
      ...newClientChoices.keys,
      ...testFields,
      ...quantityFields,
      'refer_dic',
      'remark',
    };
    if (input.keys.any((key) => !allowed.contains(key))) {
      throw ArgumentError('Unsupported encounter field');
    }
    final result = <String, Object?>{...input};
    if (result['client_code'] is String) {
      result['client_code'] = (result['client_code'] as String).trim();
    }
    if (result['client_kind'] == 'New') {
      for (final field in newClientChoices.keys) {
        if (field != 'gender') result[field] ??= newClientChoices[field]!.first;
      }
    } else {
      for (final field in newClientChoices.keys) {
        result[field] = null;
      }
    }
    return result;
  }

  Future<String> createEncounter(Row input) async {
    final owner = _owner;
    final id = _uuid.v4();
    final time = _clock();
    final stamp = time.toUtc().toIso8601String();
    await _db.transaction((tx) async {
      await tx.insert('encounters', {
        ..._input(input),
        'encounter_id': id,
        'owner_id': owner,
        'visit_date': _day(time),
        'created_at': stamp,
        'updated_at': stamp,
        'revision': 1,
      });
      final row = (await tx.query(
        'encounters',
        where: 'encounter_id = ?',
        whereArgs: [id],
      )).single;
      await _audit(tx, owner, 'encounter', id, 1, 'create', stamp, row);
    });
    return id;
  }

  Future<List<Row>> encounters() => _db.query(
    'encounters',
    where: 'owner_id = ? AND deleted_at IS NULL',
    whereArgs: [_owner],
    orderBy: 'visit_date DESC, created_at DESC, encounter_id',
  );

  Future<List<Row>> todayEncounters() => _db.rawQuery(
    '''
    SELECT e.*, h.name AS hotspot_name
    FROM encounters e JOIN hotspots h
      ON h.hotspot_id = e.hotspot_id AND h.owner_id = e.owner_id
    WHERE e.owner_id = ? AND e.visit_date = ? AND e.deleted_at IS NULL
    ORDER BY e.created_at DESC, e.encounter_id
    ''',
    [_owner, _day(_clock())],
  );

  Future<Row?> encounter(String id) async {
    final rows = await _db.query(
      'encounters',
      where: 'encounter_id = ? AND owner_id = ? AND deleted_at IS NULL',
      whereArgs: [id, _owner],
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<void> updateEncounter(
    String id,
    Row changes, {
    required int expectedRevision,
  }) => _mutate(id, changes, expectedRevision, false);

  Future<void> deleteEncounter(String id, {required int expectedRevision}) =>
      _mutate(id, const {}, expectedRevision, true);

  Future<void> _mutate(
    String id,
    Row changes,
    int expected,
    bool delete,
  ) async {
    final owner = _owner;
    final stamp = _clock().toUtc().toIso8601String();
    await _db.transaction((tx) async {
      final rows = await tx.query(
        'encounters',
        where: 'encounter_id = ? AND owner_id = ? AND deleted_at IS NULL',
        whereArgs: [id, owner],
      );
      if (rows.isEmpty) throw StateError('Record unavailable');
      final before = rows.single;
      if (before['revision'] != expected) {
        throw StateError('Record changed; reload before editing');
      }
      // Validate only editable keys, while preserving current modal state for patches.
      _input(changes);
      final editable = {...before}
        ..removeWhere(
          (k, v) => {
            'encounter_id',
            'owner_id',
            'visit_date',
            'created_at',
            'updated_at',
            'revision',
            'deleted_at',
          }.contains(k),
        );
      final revision = expected + 1;
      await tx.update(
        'encounters',
        {
          if (!delete) ..._input({...editable, ...changes}),
          'revision': revision,
          'updated_at': stamp,
          if (delete) 'deleted_at': stamp,
        },
        where: 'encounter_id = ? AND owner_id = ?',
        whereArgs: [id, owner],
      );
      final after = (await tx.query(
        'encounters',
        where: 'encounter_id = ?',
        whereArgs: [id],
      )).single;
      await _audit(
        tx,
        owner,
        'encounter',
        id,
        revision,
        delete ? 'delete' : 'update',
        stamp,
        {'before': before, 'after': after},
      );
    });
  }

  Future<Row> todaySummary() async {
    final rows = await _db.rawQuery(
      '''SELECT COUNT(*) AS client_records,
      COUNT(DISTINCT hotspot_id) AS hotspots,
      COUNT(DISTINCT client_code) AS unique_people,
      COALESCE(SUM(CASE WHEN client_kind = 'New' THEN 1 ELSE 0 END),0) AS new_clients,
      COALESCE(SUM(CASE WHEN client_kind = 'Old' THEN 1 ELSE 0 END),0) AS old_clients,
      COALESCE(SUM(CASE WHEN client_kind IS NULL THEN 1 ELSE 0 END),0) AS unspecified_clients,
      COALESCE(SUM(CASE WHEN hiv != 'No' THEN 1 ELSE 0 END),0) AS hiv_tested,
      COALESCE(SUM(CASE WHEN hiv = 'Reactive' THEN 1 ELSE 0 END),0) AS hiv_reactive,
      COALESCE(SUM(CASE WHEN hcv != 'No' THEN 1 ELSE 0 END),0) AS hcv_tested,
      COALESCE(SUM(CASE WHEN hcv = 'Reactive' THEN 1 ELSE 0 END),0) AS hcv_reactive,
      COALESCE(SUM(CASE WHEN hbv != 'No' THEN 1 ELSE 0 END),0) AS hbv_tested,
      COALESCE(SUM(CASE WHEN hbv = 'Reactive' THEN 1 ELSE 0 END),0) AS hbv_reactive,
      COALESCE(SUM(CASE WHEN syphilis != 'No' THEN 1 ELSE 0 END),0) AS syphilis_tested,
      COALESCE(SUM(CASE WHEN syphilis = 'Reactive' THEN 1 ELSE 0 END),0) AS syphilis_reactive,
      COALESCE(SUM(CASE WHEN refer_dic = 1 THEN 1 ELSE 0 END),0) AS dic_referrals,
      ${quantityFields.map((f) => 'COALESCE(SUM($f),0) AS $f').join(',')}
      FROM encounters WHERE owner_id = ? AND visit_date = ? AND deleted_at IS NULL''',
      [_owner, _day(_clock())],
    );
    return rows.single;
  }

  Future<List<Row>> pendingOperations() => _db.rawQuery(
    '''
    SELECT a.* FROM audit_operations a JOIN sync_outbox o USING(operation_id)
    WHERE a.actor_id = ? AND o.acknowledged_at IS NULL ORDER BY a.sequence''',
    [_owner],
  );

  /// Applies a validated receipt only to the exact immutable audited operations.
  /// The caller must obtain the response from the trusted pinned transport.
  /// This does not declare a whole sync complete or perform retention cleanup.
  Future<int> applySyncAcknowledgement({
    required PreparedSyncBatch sentBatch,
    required Map<String, Object?> response,
    required int httpStatus,
    String? expectedDashboardId,
  }) async {
    final owner = _owner;
    final receipt = SyncAcknowledgement.parse(
      response,
      sentBatch: sentBatch,
      httpStatus: httpStatus,
    );
    final sent = jsonDecode(sentBatch.jsonBody) as Map<String, dynamic>;
    return _db.transaction((tx) async {
      if (_owner != owner) throw StateError('Worker session changed');
      final identity = (await tx.query('app_identity', limit: 1)).single;
      if (sent['worker_id'] != owner ||
          sent['project_id'] != identity['project_id'] ||
          sent['device_id'] != identity['device_id']) {
        throw StateError('Batch identity does not match local identity');
      }
      // Check every sent operation before modifying any outbox row.
      for (final item in sent['operations'] as List) {
        final rows = await tx.rawQuery(
          'SELECT a.* FROM audit_operations a JOIN sync_outbox o USING(operation_id) '
          'WHERE a.operation_id = ? AND a.actor_id = ?',
          [item['operation_id'], owner],
        );
        if (rows.length != 1) {
          throw StateError('Local operation is unavailable');
        }
        final local = rows.single;
        for (final field in [
          'sequence',
          'operation_id',
          'actor_id',
          'entity_type',
          'entity_id',
          'revision',
          'action',
          'occurred_at',
        ]) {
          if (item[field] != local[field]) {
            throw StateError('Batch differs from local audit');
          }
        }
        if (jsonEncode(item['payload']) !=
            jsonEncode(jsonDecode(local['payload'] as String))) {
          throw StateError('Batch payload differs from local audit');
        }
      }
      final destination = (await tx.query(
        'dashboard_connection',
        limit: 1,
      )).single;
      if (expectedDashboardId != null &&
          (destination['status'] != 'Paired' ||
              destination['dashboard_id'] != expectedDashboardId)) {
        throw StateError('Receipt destination changed');
      }
      var marked = 0;
      for (final accepted in receipt.accepted) {
        marked += await tx.update(
          'sync_outbox',
          {'acknowledged_at': accepted.acceptedAt.toIso8601String()},
          where: 'operation_id = ? AND acknowledged_at IS NULL',
          whereArgs: [accepted.operationId],
        );
      }
      if (expectedDashboardId != null &&
          destination['status'] == 'Paired' &&
          destination['dashboard_id'] is String) {
        for (final accepted in receipt.accepted) {
          final op = (sent['operations'] as List).singleWhere(
            (op) => op['operation_id'] == accepted.operationId,
          );
          if (op['entity_type'] != 'encounter') continue;
          await tx.insert('sync_confirmations', {
            'operation_id': accepted.operationId,
            'worker_id': owner,
            'entity_id': op['entity_id'],
            'revision': op['revision'],
            'sequence': op['sequence'],
            'project_id': identity['project_id'],
            'device_id': identity['device_id'],
            'dashboard_id': destination['dashboard_id'],
            'batch_id': sent['batch_id'],
            'accepted_at': accepted.acceptedAt.toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      if (receipt.allAccepted) {
        final pending =
            (await tx.rawQuery(
                  '''
          SELECT COUNT(*) AS total
          FROM audit_operations a
          JOIN sync_outbox o USING(operation_id)
          WHERE a.actor_id = ? AND o.acknowledged_at IS NULL
          ''',
                  [owner],
                )).single['total']
                as int;
        if (pending == 0) {
          await tx.update(
            'sync_state',
            {
              'last_successful_sync_at': receipt.receivedAt
                  .toUtc()
                  .toIso8601String(),
            },
            where: 'worker_id = ?',
            whereArgs: [owner],
          );
        }
      }
      if (_owner != owner) throw StateError('Worker session changed');
      return marked;
    });
  }

  /// Called only after authenticated foreground Sync. Never enqueues deletion.
  Future<RetentionCleanupResult> cleanupAcknowledgedEncounters({
    required String expectedDashboardId,
    required String expectedProjectId,
    required String expectedDeviceId,
    bool Function()? mayContinue,
  }) async {
    final owner = _owner;
    final cutoff = _retentionCutoffDay();
    final stamp = _clock().toUtc().toIso8601String();
    void check() {
      if (_owner != owner || mayContinue?.call() == false) {
        throw StateError('Cleanup context changed');
      }
    }

    return _db.transaction((tx) async {
      check();
      final identity = (await tx.query('app_identity', limit: 1)).single;
      final dashboard = (await tx.query(
        'dashboard_connection',
        limit: 1,
      )).single;
      if (identity['project_id'] != expectedProjectId ||
          identity['device_id'] != expectedDeviceId ||
          dashboard['status'] != 'Paired' ||
          dashboard['dashboard_id'] != expectedDashboardId) {
        throw StateError('Cleanup destination changed');
      }
      final candidates = await retentionCandidates(
        tx,
        owner: owner,
        cutoff: cutoff,
        identity: identity,
        dashboard: dashboard,
      );
      var removed = 0;
      for (final row in candidates.eligible) {
        check();
        final args = [row['encounter_id'], owner];
        await tx.rawDelete(
          '''DELETE FROM sync_outbox WHERE operation_id IN
          (SELECT operation_id FROM audit_operations WHERE entity_type='encounter' AND entity_id=? AND actor_id=?)''',
          args,
        );
        await tx.delete(
          'audit_operations',
          where: "entity_type='encounter' AND entity_id=? AND actor_id=?",
          whereArgs: args,
        );
        removed += await tx.delete(
          'encounters',
          where: 'encounter_id=? AND owner_id=? AND revision=?',
          whereArgs: [...args, row['revision']],
        );
      }
      await tx.update(
        'sync_state',
        {
          'retention_checked_at': stamp,
          if (removed > 0) 'retention_cleanup_at': stamp,
          'retention_last_eligible': candidates.eligible.length,
          'retention_last_held': candidates.held,
          'retention_last_removed': removed,
        },
        where: 'worker_id=?',
        whereArgs: [owner],
      );
      check();
      return RetentionCleanupResult(
        eligible: candidates.eligible.length,
        held: candidates.held,
        removed: removed,
      );
    });
  }

  Future<Row> syncStatus() async {
    final owner = _owner;
    final pending = (await _db.rawQuery(
      '''
        SELECT COUNT(*) AS total,
        COALESCE(SUM(CASE WHEN a.entity_type = 'worker' THEN 1 ELSE 0 END),0) AS workers,
        COALESCE(SUM(CASE WHEN a.entity_type = 'hotspot' THEN 1 ELSE 0 END),0) AS hotspots,
        COALESCE(SUM(CASE WHEN a.entity_type = 'encounter' THEN 1 ELSE 0 END),0) AS encounters,
        COALESCE(SUM(CASE WHEN a.action = 'create' THEN 1 ELSE 0 END),0) AS creates,
        COALESCE(SUM(CASE WHEN a.action = 'update' THEN 1 ELSE 0 END),0) AS updates,
        COALESCE(SUM(CASE WHEN a.action = 'delete' THEN 1 ELSE 0 END),0) AS deletes
        FROM audit_operations a
        JOIN sync_outbox o USING(operation_id)
        WHERE a.actor_id = ? AND o.acknowledged_at IS NULL
        ''',
      [owner],
    )).single;
    final state = (await _db.query(
      'sync_state',
      where: 'worker_id = ?',
      whereArgs: [owner],
      limit: 1,
    )).single;
    final identity = await appIdentity();
    final dashboard = (await _db.query(
      'dashboard_connection',
      limit: 1,
    )).single;
    final retention = await retentionCandidates(
      _db,
      owner: owner,
      cutoff: _retentionCutoffDay(),
      identity: identity,
      dashboard: dashboard,
    );
    return {
      'pending_operations': pending['total'] ?? 0,
      'pending_workers': pending['workers'] ?? 0,
      'pending_hotspots': pending['hotspots'] ?? 0,
      'pending_encounters': pending['encounters'] ?? 0,
      'pending_creates': pending['creates'] ?? 0,
      'pending_updates': pending['updates'] ?? 0,
      'pending_deletes': pending['deletes'] ?? 0,
      'last_successful_sync_at': state['last_successful_sync_at'],
      'retention_checked_at': state['retention_checked_at'],
      'retention_cleanup_at': state['retention_cleanup_at'],
      'retention_keep_days': _retentionKeepDays,
      'retention_cutoff_day': _retentionCutoffDay(),
      'old_client_records': retention.eligible.length + retention.held,
      'old_client_records_held_unsynced': retention.held,
      'old_client_records_eligible_after_ack': retention.eligible.length,
      'retention_cleanup_enabled': 1,
      'retention_last_eligible': state['retention_last_eligible'],
      'retention_last_held': state['retention_last_held'],
      'retention_last_removed': state['retention_last_removed'],
      'project_id': identity['project_id'],
      'project_name': identity['project_name'],
      'device_id': identity['device_id'],
      'device_created_at': identity['created_at'],
      'dashboard_status': dashboard['status'],
      'dashboard_url': dashboard['dashboard_url'],
      'dashboard_name': dashboard['dashboard_name'],
      'dashboard_id': dashboard['dashboard_id'],
      'paired_at': dashboard['paired_at'],
      'pairing_code_saved':
          (dashboard['pairing_code'] as String?)?.trim().isNotEmpty == true
          ? 1
          : 0,
      'pairing_prepared_at': dashboard['pairing_prepared_at'],
    };
  }

  Future<void> saveDashboardPairing(String address, String pairingCode) async {
    final value = address.trim();
    final code = pairingCode.trim();
    if (value.isEmpty) throw ArgumentError('Dashboard address is required');
    if (code.isEmpty) throw ArgumentError('Pairing code is required');
    final stamp = _clock().toUtc().toIso8601String();
    await _db.transaction((txn) async {
      final existing = (await txn.query(
        'dashboard_connection',
        limit: 1,
      )).single;
      if (existing['status'] == 'Paired') {
        if (existing['dashboard_url'] == value) return;
        throw StateError(
          'Clear the existing pairing before changing dashboards.',
        );
      }
      await txn.update('dashboard_connection', {
        'dashboard_url': value,
        'pairing_code': code,
        'pairing_prepared_at': stamp,
        'status': 'Not configured',
        'dashboard_id': null,
        'dashboard_name': null,
        'paired_at': null,
        'updated_at': stamp,
      }, where: 'singleton_id = 1');
    });
  }

  Future<Row> dashboardPairingPreparation() async =>
      (await _db.query('dashboard_connection', limit: 1)).single;

  Future<void> applyDashboardPairing(PairingSuccess success) async {
    final stamp = _clock().toUtc().toIso8601String();
    final updated = await _db.update(
      'dashboard_connection',
      {
        'status': 'Paired',
        'dashboard_id': success.dashboardId,
        'dashboard_name': success.dashboardName,
        'paired_at': success.pairedAt.toUtc().toIso8601String(),
        'pairing_code': null,
        'pairing_prepared_at': null,
        'updated_at': stamp,
      },
      where: 'singleton_id = 1 AND dashboard_url IS NOT NULL',
    );
    if (updated != 1) {
      throw StateError('Dashboard pairing information is not prepared.');
    }
  }

  Future<void> clearDashboardAddress() async {
    await _db.update('dashboard_connection', {
      'dashboard_url': null,
      'pairing_code': null,
      'pairing_prepared_at': null,
      'status': 'Not configured',
      'dashboard_id': null,
      'dashboard_name': null,
      'paired_at': null,
      'updated_at': _clock().toUtc().toIso8601String(),
    }, where: 'singleton_id = 1');
  }
}
