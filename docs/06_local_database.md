# Local SQLite implementation

Current SQLite schema version: 4. Version 2 added authentication credentials; version 3 adds app/device identity for future dashboard sync; version 4 adds local dashboard connection state. Android production builds now open the database through SQLCipher; phone migration verification remains pending.

## Scope

Implemented database version 1 using SQLite. At startup the APK opens or creates ansvk_outreach.db in Android's private database directory. Production Android opening now uses SQLCipher with a generated local database passphrase stored through Android-backed secure storage. No sample workers or client records are inserted by the app.

The SQLite file is on the phone, not embedded with user records inside the APK. The APK contains the code that creates the tables. Opening the database again preserves existing data.

## Tables

| Table | Purpose |
| --- | --- |
| workers | Generated worker ID, unique local username and creation time |
| hotspots | Owner, name, nullable GPS and status, creation time and revision |
| hotspot_peers | Ordered typed peer names for each hotspot |
| encounters | Worker/hotspot, client code, visit date, all client/testing/supply/referral fields, timestamps, revision and deletion marker |
| audit_operations | Ordered create/edit/delete history with actor, operation ID, entity, revision and JSON snapshots |
| sync_outbox | Persistent pending-operation tracking; acknowledgement fields reserved for future sync |
| sync_state | Per-worker last-successful-sync field, initially empty |
| credentials | Password verifier material linked to a worker; added in schema version 2 |
| app_identity | One local project/device identity row for future dashboard sync; added in schema version 3 |
| dashboard_connection | One local dashboard pairing/address state row; added in schema version 4 |

There is no permanent client directory. SQLite's internal sqlite_sequence table also appears because audit operations use an incrementing sequence.

## Code organization

- lib/database/schema.dart: numbered migrations, columns, indexes, constraints and triggers.
- lib/database/app_database.dart: database opening, SQLCipher production access, foreign-key activation, versioning, one-time plaintext development migration and close lifecycle.
- lib/database/database_key_store.dart: generated local SQLCipher passphrase storage using flutter_secure_storage.
- lib/database/outreach_repository.dart: worker-scoped storage methods and atomic mutation/audit/outbox transactions.
- lib/main.dart: awaits database creation before showing the existing app shell.
- test/database_test.dart: native SQLite tests with isolated temporary database files.

Future schema changes must add numbered migrations and increment the schema version. Unsupported downgrades fail rather than deleting the database. Existing historical migrations now cover version 1 → 2 credentials, version 2 → 3 app identity and version 3 → 4 dashboard connection state.

## Implemented guarantees

- A composite foreign key prevents assigning an encounter to another worker's hotspot.
- Repository reads and mutations obtain ownership from a supplied session callback. A missing session fails; the future authentication layer must supply this callback. Form fields cannot override owner, ID, date or revision.
- A partial unique index prevents two active encounters for the same worker/client code/hotspot/day. Client codes are trimmed and case-sensitive, with leading zeros preserved.
- Edits preserve original owner, ID, creation timestamp and visit date. Expected revisions reject stale edits.
- Deletes are soft deletions: records leave active lists and totals while audit history and pending deletion operations remain.
- Hotspot updates are prohibited in version 1.
- All quantity fields accept non-negative whole numbers; categories, required codes and GPS consistency are constrained.
- A mutation, audit entry and pending operation commit together or all roll back.
- Daily database queries count distinct client codes for unique people and filter by worker, local day and active state.
- No acknowledgement or seven-day cleanup is implemented, so older unsynchronized data cannot be removed automatically.
- The app identity row is created automatically. It is local configuration, not a worker-entered record and not an audited worker operation.
- The dashboard connection row is created automatically as Not configured. It is local configuration, not a sync acknowledgement and not an audited worker operation.

## Verification

Nine database tests plus authentication migration tests passed. They cover table creation and integrity, app identity creation/persistence, version-1 upgrade to current schema, reopen persistence, ownership, duplicate keys across sites/days/workers, concurrent saves, input constraints, New/Old transitions, immutable dates, stale revisions, deletion/replacement, transactional rollback and daily unique-person totals.

Tests run through sqflite_common_ffi against real SQLite files on the development computer, not a mocked SQL engine. Android SQLCipher integration is checked through the debug APK build and still needs phone install/migration verification.

Implementation references: [sqflite_sqlcipher](https://pub.dev/packages/sqflite_sqlcipher), [flutter_secure_storage](https://pub.dev/documentation/flutter_secure_storage/latest/), [native SQLite test backend](https://pub.dev/packages/sqflite_common_ffi), [SQLite foreign keys](https://www.sqlite.org/foreignkeys.html), [partial indexes](https://www.sqlite.org/partialindex.html).

## Deliberately deferred

Registration, password verification/storage, authentication, inactivity locking, screens and GPS acquisition are implemented in later increments. Network sync and retention cleanup remain outside this database-only step. createWorkerProfile is infrastructure provisioning only and does not create a usable login.

Android app-private storage, allowBackup=false and SQLCipher database opening are configured. Do not use this development build for real client information until phone migration verification, release signing and pilot checks are complete. Raw connection access is restricted by convention to infrastructure/tests; repository scoping is not a substitute for OS security or the future authentication layer.
