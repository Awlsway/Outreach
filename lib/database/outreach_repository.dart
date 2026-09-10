import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'app_database.dart';
import 'schema.dart';

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

  String get _owner {
    final value = currentWorkerId();
    if (value == null || value.isEmpty) throw StateError('No worker session');
    return value;
  }

  static String _day(DateTime time) =>
      '${time.year.toString().padLeft(4, '0')}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';

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
      '''SELECT COUNT(DISTINCT hotspot_id) AS hotspots,
      COUNT(DISTINCT client_code) AS clients_served,
      COALESCE(SUM(CASE WHEN hiv != 'No' THEN 1 ELSE 0 END),0) AS hiv_tested,
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
}
