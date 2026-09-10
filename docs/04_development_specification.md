# ANSVK Outreach development specification

Status: Android foundation, SQLite schema v2, offline accounts/lock and hotspot workflow implemented. See 05_build_status.md for validation, 07_accounts_and_lock.md for accounts, and 08_hotspots.md for hotspots.

This specification implements 01_plan.md and the acceptance checks in 02_implementation_plan.md. Defaults below are project-manager decisions, not additional user-confirmed requirements. They allow development to proceed and can be revised without changing the confirmed scope.

## Technology decision

Use Flutter with Dart for the Android application and SQLite for structured offline storage. Flutter 3.44.1 and Dart 3.12.1 are installed at D:/flutter/bin; Java 17 and Android SDK 36.0.0 passed Flutter doctor. SQLite version-1 schema and repositories are implemented; see 06_local_database.md. See 05_build_status.md for build results.

Flutter provides Android deployment and documented SQLite persistence support. Native Kotlin with Room is a viable alternative, but Flutter uses the existing local toolchain and fits the form-based workflow. This selection is a project fit decision, not a claim that Flutter is universally preferable.

References: [Flutter Android support](https://docs.flutter.dev/reference/supported-platforms), [Flutter SQLite persistence](https://docs.flutter.dev/cookbook/persistence/sqlite), [Android Room](https://developer.android.com/training/data-storage/room), and [Android offline-first architecture](https://developer.android.com/topic/architecture/data-layer/offline-first).

Use a repository layer between screens and local storage. All normal reads and writes use the local database. Sync is a separate, manually triggered adapter; UI entry must never depend on a network response. Evaluate and pin exact package versions during scaffold creation. Do not choose a minimum Android version until checking the installed Flutter SDK and dependencies; real-device compatibility is a pilot check rather than a planning blocker.

## Working defaults now in effect

- New/Old starts unselected and may remain unspecified, preserving the requirement that only client code is mandatory. Show an explicit Not specified state instead of silently treating it as Old.
- Gender starts unselected and is optional. All supplied previous-status and user-type defaults remain unchanged.
- Current tests default to No (not tested); DIC referral defaults to No.
- Trim surrounding whitespace from client codes, preserve leading zeros and preserve case. Use the same stored code for duplicate checks and unique-person counts. Case-insensitive normalization can be added later if the user requests it.
- A saved encounter keeps the selected hotspot and resets all client fields, including modal state and quantities.
- Missing GPS uses null coordinates and an Unavailable label. Do not substitute 0,0.
- Password unlock resumes an in-memory draft. A process shutdown may lose an unsaved draft; saved records must survive.
- Keep today and the preceding six local dates. Older acknowledged records are eligible for removal; unsynchronized records never expire.
- Use local calendar dates for daily entry and totals, and UTC timestamps for audit events. Existing visit dates are immutable during edits.
- Count distinct active hotspots, distinct client codes, HIV encounters with a result other than No, and separate quantities per distributed item. The unique-client definition is user-confirmed; other summary choices follow earlier proposals.
- Use a fresh form layout based on these fields; no reference form is required to start.

## Field dictionary

| Group | Field | Storage and behavior |
| --- | --- | --- |
| Account | worker_id | Generated stable ID; never use username as a global identity |
| Account | username | Required at registration; trim; enforce local uniqueness |
| Account | password verifier | Salted password-derived verifier; never plaintext; algorithm and parameters selected during security implementation |
| Hotspot | hotspot_id, owner_id | Generated ID and immutable creator/owner |
| Hotspot | name | Trimmed text; require a usable name to create the hotspot |
| Hotspot | peers | Ordered list of typed names; multiple allowed; no fixed directory |
| Hotspot | latitude, longitude, location_status | Nullable coordinates with Available/Unavailable state |
| Hotspot | created_at | UTC creation timestamp |
| Encounter | encounter_id, owner_id, hotspot_id | Generated ID; owner fixed to session; hotspot must belong to owner |
| Encounter | client_code | Required trimmed text; leading zeros preserved |
| Encounter | visit_date | Local YYYY-MM-DD, assigned on initial save; no date picker |
| Encounter | client_kind | New, Old, or null (Not specified) |
| New-client modal | user_type | PWID default; PWUD, SPOUS, MSM, FSW, FM, Youth, Other |
| New-client modal | gender | Male, Female, or null |
| New-client modal | previous_hiv, previous_hcv | Unknown default; Positive, Negative |
| New-client modal | previous_hbv | Unknown default; Positive, Negative, Vaccinated |
| New-client modal | previous_mmt | No default; Drop Out, Current |
| New-client modal | previous_art | No default; Defaulter, Current |
| Tests | hiv, hcv, hbv, syphilis | No default; Non reactive, Reactive |
| Distribution | dist_3cc, dist_1cc, dist_lds, dist_alcohol_swab, dist_sterile_water, dist_condom | Integer >= 0; default 0 |
| Recollection | recollect_3cc, recollect_1cc, recollect_lds | Integer >= 0; default 0 |
| Referral | refer_dic | Boolean; default false |
| Encounter | remark | Optional text |
| Record metadata | created_at, updated_at, revision, deleted_at | UTC timestamps; increasing revision; nullable deletion marker |

Client-code-only required input applies to the encounter form, not account registration. The required hotspot name is an implementation default for usable search. Switching away from New excludes modal fields from the saved encounter; changing back before save may restore the unsaved modal draft. Do not copy new-client information into Old encounters automatically.

## Database invariants and operations

Tables: workers, hotspots, hotspot_peers, encounters, audit_operations, sync_outbox, sync_state. No permanent client table is needed. Use schema migrations from version 1.

- Every repository call obtains the worker ID from the authenticated session, rather than trusting an ID passed from a form.
- Encounters reference hotspots belonging to the same worker. Apply this rule on insert and update.
- Enforce a unique key on owner_id, client_code, hotspot_id and visit_date for nondeleted encounters. Deletion permits a replacement encounter while preserving the old encounter ID and pending deletion.
- Mutation, audit entry and outbox insertion commit together. A failed transaction must leave all three unchanged.
- Each operation has a generated ID for retry deduplication. Queue revisions in order for an entity.
- Audit excludes credentials. Client-identifying historical payloads follow the same safe purge conditions as their records.
- Summary queries use the signed-in worker, today's visit_date and deleted_at IS NULL. Clients served uses COUNT(DISTINCT client_code).
- Cleanup uses the latest acknowledged revision. An acknowledgement of revision 1 does not authorize removing locally edited revision 2.

## Future desktop API draft

This is a proposed contract for the desktop team; no server or endpoint currently exists.

1. Pair through an explicit office-server configuration and authenticated pairing flow. Transport trust and account reconciliation must be implemented before production sync. Never disable certificate checks to make LAN connection work.
2. POST /api/v1/sync/batches sends protocol version, device ID, worker ID, batch ID and ordered operations. Operations contain operation ID, entity type/ID, revision, action, timestamp and payload.
3. Desktop durably stores accepted operations before returning acknowledgements keyed by operation ID and revision. Include rejected operations with machine-readable reason and retryability.
4. Mobile marks only matching operations acknowledged. Retry unchanged operation IDs after timeout; a new batch ID must not defeat operation deduplication.
5. Apply hotspot creation before dependent encounters. A rejected hotspot cannot leave its encounter incorrectly marked synchronized.
6. Upload deletes as explicit operations, not silent disappearance. Never send password verifiers as part of the data batch.
7. Once the worker's eligible changes are acknowledged, run local retention cleanup transactionally. Interrupted cleanup must be safe to retry.

No automatic background syncing. The first APK may show Sync with an explanatory Desktop connection not configured state and pending-change count. A development fake service must not be packaged as a successful production connection.

## Ordered development backlog

| Order | Item | Deliverable | Acceptance reference |
| --- | --- | --- | --- |
| 1 | Validate toolchain and scaffold Android-only Flutter project | SDK/build findings, package versions, launchable app shell | M2, A18 |
| 2 | Implement schema and repositories | Migrations, transactional writes, ownership and uniqueness constraints | A02, A08, A14 |
| 3 | Implement local authentication and lock | Registration/login, credential storage, session timeout, background concealment | A01–A03 |
| 4 | Implement hotspots | Search, creation, typed peers, location permission and fallback | A04–A05 |
| 5 | Implement encounter entry | All fields/defaults, New modal, validation, save/reset | A06–A09, A11–A12 |
| 6 | Implement own-record management | List/detail/edit/delete with audit tracking | A02, A08, A10 |
| 7 | Implement daily summary | Distinct clients and hotspots; tests and supply totals | A13 |
| 8 | Implement sync preparation | Persistent queue, unavailable connection UI, development acknowledgement tests | A14–A17 |
| 9 | Verify release and pilot | APK, installation instructions, evidence and known limitations | A01–A18 |

## Implementation and pilot constraints

Credential recovery and storage protection must be resolved before a real-data pilot. Use platform-backed key protection as appropriate; [Android Keystore](https://developer.android.com/privacy-and-security/keystore) documents protected key storage, but does not by itself encrypt a SQLite database. Select and validate the complete storage design during foundation work. Do not silently enable cloud backups of client records. Do not erase unsynced records as a password-recovery shortcut.

No live desktop sync, real-device compatibility or release security claims are made by this design document. Those require implementation and evidence. They do not block starting the development backlog.
