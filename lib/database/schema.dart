import 'package:sqflite/sqflite.dart';

const quantityFields = [
  'dist_3cc',
  'dist_1cc',
  'dist_lds',
  'dist_alcohol_swab',
  'dist_sterile_water',
  'dist_condom',
  'recollect_3cc',
  'recollect_1cc',
  'recollect_lds',
];
const testFields = ['hiv', 'hcv', 'hbv', 'syphilis'];
const newClientChoices = <String, List<String>>{
  'user_type': ['PWID', 'PWUD', 'SPOUS', 'MSM', 'FSW', 'FM', 'Youth', 'Other'],
  'gender': ['Male', 'Female'],
  'previous_hiv': ['Unknown', 'Positive', 'Negative'],
  'previous_hcv': ['Unknown', 'Positive', 'Negative'],
  'previous_hbv': ['Unknown', 'Positive', 'Negative', 'Vaccinated'],
  'previous_mmt': ['No', 'Drop Out', 'Current'],
  'previous_art': ['No', 'Defaulter', 'Current'],
};

/// Version 1 is the initial schema. Future versions append migrations here;
/// existing installations must never be recreated to upgrade them.
Future<void> migrate(Database db, int from, int to) async {
  if (from < 1 && to >= 1) {
    final statements = [
      '''CREATE TABLE workers (
        worker_id TEXT PRIMARY KEY NOT NULL,
        username TEXT NOT NULL UNIQUE CHECK(length(trim(username)) > 0),
        created_at TEXT NOT NULL
      )''',
      '''CREATE TABLE hotspots (
        hotspot_id TEXT PRIMARY KEY NOT NULL,
        owner_id TEXT NOT NULL REFERENCES workers(worker_id),
        name TEXT NOT NULL CHECK(length(trim(name)) > 0),
        latitude REAL, longitude REAL,
        location_status TEXT NOT NULL DEFAULT 'Unavailable',
        created_at TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 1 CHECK(revision > 0),
        UNIQUE(hotspot_id, owner_id),
        CHECK((location_status = 'Unavailable' AND latitude IS NULL AND longitude IS NULL)
          OR (location_status = 'Available' AND latitude IS NOT NULL AND longitude IS NOT NULL
          AND latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180))
      )''',
      '''CREATE TABLE hotspot_peers (
        hotspot_id TEXT NOT NULL REFERENCES hotspots(hotspot_id),
        position INTEGER NOT NULL CHECK(position >= 0),
        name TEXT NOT NULL CHECK(length(trim(name)) > 0),
        PRIMARY KEY(hotspot_id, position)
      )''',
      '''CREATE TABLE encounters (
        encounter_id TEXT PRIMARY KEY NOT NULL,
        owner_id TEXT NOT NULL REFERENCES workers(worker_id),
        hotspot_id TEXT NOT NULL,
        client_code TEXT NOT NULL CHECK(length(trim(client_code)) > 0 AND client_code = trim(client_code)),
        visit_date TEXT NOT NULL CHECK(length(visit_date) = 10 AND date(visit_date) IS NOT NULL AND date(visit_date) = visit_date),
        client_kind TEXT CHECK(client_kind IN ('New', 'Old')),
        ${newClientChoices.entries.map((e) => "${e.key} TEXT CHECK(${e.key} IN (${e.value.map((v) => "'$v'").join(',')}))").join(',\n')},
        ${testFields.map((f) => "$f TEXT NOT NULL DEFAULT 'No' CHECK($f IN ('No', 'Non reactive', 'Reactive'))").join(',\n')},
        ${quantityFields.map((f) => "$f INTEGER NOT NULL DEFAULT 0 CHECK(typeof($f) = 'integer' AND $f >= 0)").join(',\n')},
        refer_dic INTEGER NOT NULL DEFAULT 0 CHECK(refer_dic IN (0,1)),
        remark TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 1 CHECK(revision > 0),
        deleted_at TEXT,
        FOREIGN KEY(hotspot_id, owner_id) REFERENCES hotspots(hotspot_id, owner_id),
        CHECK(client_kind IS 'New' OR (${newClientChoices.keys.map((f) => '$f IS NULL').join(' AND ')}))
      )''',
      '''CREATE UNIQUE INDEX unique_active_encounter
        ON encounters(owner_id, client_code, hotspot_id, visit_date)
        WHERE deleted_at IS NULL''',
      'CREATE INDEX encounters_daily ON encounters(owner_id, visit_date) WHERE deleted_at IS NULL',
      'CREATE INDEX hotspots_owner ON hotspots(owner_id, name)',
      '''CREATE TABLE audit_operations (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_id TEXT NOT NULL UNIQUE,
        actor_id TEXT NOT NULL REFERENCES workers(worker_id),
        entity_type TEXT NOT NULL CHECK(entity_type IN ('worker', 'hotspot', 'encounter')),
        entity_id TEXT NOT NULL,
        revision INTEGER NOT NULL CHECK(revision > 0),
        action TEXT NOT NULL CHECK(action IN ('create', 'update', 'delete')),
        occurred_at TEXT NOT NULL,
        payload TEXT NOT NULL,
        UNIQUE(entity_type, entity_id, revision)
      )''',
      '''CREATE TABLE sync_outbox (
        operation_id TEXT PRIMARY KEY NOT NULL REFERENCES audit_operations(operation_id),
        acknowledged_at TEXT,
        attempts INTEGER NOT NULL DEFAULT 0 CHECK(attempts >= 0),
        last_error TEXT
      )''',
      '''CREATE TABLE sync_state (
        worker_id TEXT PRIMARY KEY NOT NULL REFERENCES workers(worker_id),
        last_successful_sync_at TEXT
      )''',
      '''CREATE TRIGGER encounter_identity_immutable BEFORE UPDATE ON encounters
        WHEN NEW.encounter_id != OLD.encounter_id OR NEW.owner_id != OLD.owner_id
          OR NEW.visit_date != OLD.visit_date OR NEW.created_at != OLD.created_at
        BEGIN SELECT RAISE(ABORT, 'Encounter identity and visit date are immutable'); END''',
      '''CREATE TRIGGER hotspot_immutable BEFORE UPDATE ON hotspots
        BEGIN SELECT RAISE(ABORT, 'Hotspot editing is not supported'); END''',
    ];
    for (final sql in statements) {
      await db.execute(sql);
    }
  }
  if (from < 2 && to >= 2) {
    await db.execute('''CREATE TABLE credentials (
      worker_id TEXT PRIMARY KEY NOT NULL REFERENCES workers(worker_id),
      algorithm TEXT NOT NULL CHECK(algorithm = 'pbkdf2-sha256'),
      iterations INTEGER NOT NULL CHECK(iterations >= 600000),
      salt TEXT NOT NULL,
      verifier TEXT NOT NULL,
      failed_attempts INTEGER NOT NULL DEFAULT 0 CHECK(failed_attempts >= 0),
      blocked_until TEXT
    )''');
  }
}
