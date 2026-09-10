# Local SQLite implementation

Historical database-only increment: current schema version 2 and authentication additions are documented in 07_accounts_and_lock.md. The deferred-registration statements below describe version 1.

## Scope

Implemented database version 1 using sqflite 2.4.3. At startup the APK opens or creates ansvk_outreach.db in Android's private database directory. No sample workers or client records are inserted by the app. The preview UI remains unchanged.

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

There is no permanent client directory. SQLite's internal sqlite_sequence table also appears because audit operations use an incrementing sequence.

## Code organization

- lib/database/schema.dart: initial migration, columns, indexes, constraints and triggers.
- lib/database/app_database.dart: database opening, foreign-key activation, versioning and close lifecycle.
- lib/database/outreach_repository.dart: worker-scoped storage methods and atomic mutation/audit/outbox transactions.
- lib/main.dart: awaits database creation before showing the existing app shell.
- test/database_test.dart: native SQLite tests with isolated temporary database files.

Future schema changes must add numbered migrations and increment the schema version. Unsupported downgrades fail rather than deleting the database. There are no historical schema versions to migrate yet.

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

## Verification

Nine database tests plus the existing launch test passed. They cover table creation and integrity, reopen persistence, ownership, duplicate keys across sites/days/workers, concurrent saves, input constraints, New/Old transitions, immutable dates, stale revisions, deletion/replacement, transactional rollback and daily unique-person totals. Code analysis passed with no issues.

Tests run through sqflite_common_ffi against real SQLite files on the development computer, not a mocked SQL engine. Device creation is checked separately in 05_build_status.md.

Implementation references: [sqflite](https://pub.dev/packages/sqflite), [native SQLite test backend](https://pub.dev/packages/sqflite_common_ffi), [SQLite foreign keys](https://www.sqlite.org/foreignkeys.html), [partial indexes](https://www.sqlite.org/partialindex.html).

## Deliberately deferred

Registration, password verification/storage, authentication, inactivity locking, encryption, screens, GPS acquisition, network sync and retention cleanup are outside this database-only step. createWorkerProfile is infrastructure provisioning only and does not create a usable login. Credential schema will be added with the selected authentication design in a subsequent migration.

Android app-private storage and allowBackup=false are configured; database encryption is not yet implemented. Do not use this development build for real client information. Raw connection access is restricted by convention to infrastructure/tests; repository scoping is not a substitute for OS security or the future authentication layer.
