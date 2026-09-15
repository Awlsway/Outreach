# Scaffold build status

## Dashboard pairing preparation (0.9.1+16)

- Added SQLite schema version 5 fields on `dashboard_connection` for a locally saved future pairing code and pairing-prepared timestamp.
- Updated Sync Status to show address saved, pairing code saved, ready to request pairing, dashboard paired and ready to sync as separate checks.
- Updated the dashboard setup screen to save a local dashboard API address plus a 4-12 digit pairing code. This prepares a later dashboard pairing request only; it does not contact the dashboard, upload data, acknowledge operations or clean up records.
- Validation completed on the development computer: full Flutter test suite passed with `--concurrency=1`, and debug APK 0.9.1+16 built successfully.
- Phone install over existing test data succeeded on device `ORCE49UWDQVGRC49`. User phone walkthrough passed: Dashboard pairing accepted a local dashboard address and pairing code, Sync Status showed address/code prepared, and real sync remained unavailable because the Windows dashboard is not built yet.

## Database encryption implementation (0.9.0+15)

- Added SQLCipher database opening for production Android through `sqflite_sqlcipher`.
- Added `flutter_secure_storage` for a generated local database passphrase. The passphrase is created by the app, stored locally, and is not derived from the worker password.
- Removed the direct plain `sqflite` app dependency. Tests still use `sqflite_common_ffi` through an injected database factory.
- Added a one-time plaintext development-database migration path. If the existing `ansvk_outreach.db` is a valid unencrypted development database, the app exports it into an encrypted SQLCipher database, verifies integrity, replaces the old file only after verification, and does not silently delete data after a failed migration.
- Added Android SQLCipher ProGuard keep rule.
- Validation completed on the development computer: full Flutter test suite passed, and debug APK 0.9.0+15 built successfully.
- Phone install over existing test data succeeded on device `ORCE49UWDQVGRC49`. Cold launch put `org.ansvk.ansvk_outreach/.MainActivity` in the foreground with no Flutter/AndroidRuntime crash logs.
- Header-only inspection of `databases/ansvk_outreach.db` showed encrypted-looking bytes instead of the plain SQLite `SQLite format 3` header. No table contents or client records were read.
- User phone walkthrough passed after migration: sign-in worked, existing data remained visible, a new test record could be added, and data remained after reopening.

## Sync status preparation

- Added a signed-in **Sync status** screen.
- The screen reads the real pending-operation count from the local audit/outbox tables and shows a breakdown by worker, hotspot, client-record, create, update and delete operations.
- Added SQLite schema version 4 with a local `dashboard_connection` row. It currently stores **Not configured** plus empty dashboard address/pairing fields, so future pairing can update stored state instead of replacing hard-coded UI text.
- It shows desktop connection status, dashboard name/address, pairing time, last successful sync and local app identity information for future support.
- Added a **Sync readiness** section that separates saved address, pairing status and real sync readiness. Real sync remains **No** until the dashboard pairing/upload work exists.
- Added worker-facing guidance that Sync Status is only for checking pending changes until the office dashboard is built and paired.
- Added a **Pending changes** detail screen from Sync Status. It lists pending operation type/action/revision/time only, not full payload data.
- Added a **Dashboard address** screen from Sync Status. It saves or clears a local `http://...` dashboard API address only; it does not pair, test the connection, upload, acknowledge or clean up data.
- The Sync action is disabled with the message that dashboard setup is required. No upload, acknowledgement, fake success or retention cleanup is implemented.
- Debug APK 0.8.2+14 built successfully and installed on the connected phone with `adb install -r`, preserving existing data. The app launched successfully. The user tested Sync Status, pending changes, dashboard address save/clear and confirmed the increment passed.

## App identity database migration (0.8.1+13)

- Added SQLite schema version 3 with a local `app_identity` table.
- The APK auto-creates one app identity row during database creation or upgrade. Workers do not fill a form for this.
- The row stores `project_id`, `project_name`, a generated `device_id` and `created_at`. Future sync batches can use this information so the Windows dashboard knows which project/app/device sent the data.
- No phone install was performed for this increment. Verification was local only: database tests passed, and auth migration tests passed including a version-1-to-version-3 upgrade.

## Record edit update (0.8.0+12)

- Added Edit record from Record detail.
- Edit reuses the client-entry form with the client code locked and the original hotspot/visit date unchanged.
- Workers can update client type, New-client details, tests, quantities, DIC referral and remark. Successful updates create an audit/outbox update operation for future sync.
- Added a top-right save action on the edit screen so workers do not have to scroll to the bottom to update a long record.
- Focused verification passed: hotspot workspace edit UI test, database tests and client-entry widget tests.

## Record delete update (0.7.1+11)

- Added Delete record on the record detail page, with an in-app confirmation dialog.
- Delete uses the existing soft-delete repository operation, so the record disappears from Today's records and Daily summary while a delete operation remains queued for future sync.
- Focused verification passed: hotspot workspace delete UI test, database tests and client-entry widget tests.

## Today records update (0.7.0+10)

- Added a signed-in home action for Today's records.
- The list shows only the current worker's active records for today's visit date, with client code, hotspot, client type, tested markers and saved time.
- Added a read-only detail page showing client fields, tests, distribution, recollection, DIC referral, saved time and remark. Edit/delete remain the next chunk.
- Focused verification passed: database tests, client-entry widget tests and hotspot workspace widget tests including list/detail navigation.

## Daily summary update (0.6.0+9)

- Added a phone-side Daily Summary screen from the signed-in home page. It counts only the signed-in worker's active local records for today.
- Summary totals include hotspots, records, unique people by client code, DIC referrals, New/Old/Not specified client type, tested/reactive counts for HIV/HCV/HBV/Syphilis, distribution totals and recollection totals.
- Focused verification passed: database summary totals and hotspot workspace Daily Summary UI tests.

## Encounter layout polish (0.5.0+7)

- Enlarged the Testing, Distribution and Recollection headings.
- Grouped distribution into a teal needles-and-syringes row and a contrasting other-supplies row. Grouped recollection into one separate colored row. Each row retains its three original quantity fields and database keys.

## Client-code input polish (0.4.1+6)

- Replaced the free-text client-code field with four-digit year, fixed `/MY/`, and 1–4 digit number inputs. The number is zero-padded on save, so `4` becomes `YYYY/MY/0004`.
- Added spacing between New-client dropdown fields so adjoining outlined controls no longer appear to overlap.

## Client-entry update (0.4.0+5)

- Added the client-entry form from a selected hotspot. It requires a client code, supports optional New/Old classification, uses the confirmed New-client fields and defaults, and records test results, distributions, recollections, DIC referral and an optional remark.
- The visit date is assigned locally on save. SQLite rejects a second active record for the same worker, client code, hotspot and date; the form explains that conflict and keeps the entered data. Quantities accept only nonnegative whole numbers.
- A successful save writes the encounter, audit operation and future-sync outbox operation transactionally, then clears the client fields while keeping the selected hotspot ready for the next record.
- Focused widget checks passed for the complete New-client save/reset flow and validation/duplicate handling. The full suite passed: 29 tests. `flutter analyze --no-pub` completed with no diagnostics. After regenerating Flutter package metadata, the debug APK was verified as version 0.4.0/build 5 and installed with `adb install -r` on the connected Android 16 phone, which preserves existing app data. A cold launch completed successfully in 1861 ms. No client record was created by the agent on the phone.

## Hotspot update (0.3.0+4)

- Implemented owned hotspot list/search, new-hotspot form with typed peers, and read-only selection details. GPS supports permission handling, a 20-second attempt budget, retry and null-coordinate fallback.
- Code analysis passed. All 27 tests passed, including simulated GPS success/denial/disabled/timeout, two-hotspot creation/search, draft preservation and cross-worker isolation.
- First Android build failed because Kotlin incremental cache paths spanned the C: package cache and D: workspace. Set kotlin.incremental=false in project android/gradle.properties, following [Kotlin's documented setting](https://kotlinlang.org/docs/gradle-compilation-and-caches.html). Rebuild succeeded in 20.0 seconds. No user data or global build settings were changed.
- Updated APK installed on the connected Android 16 phone without clearing app data. Cold launch returned Status: ok, 1984 ms.
- Follow-up: the user created two hotspots and confirmed the result. Read-only inspection of a stable phone database snapshot found one with real coordinates and Available status, and one with null coordinates and Unavailable status. Both belong to the same worker; creation audit payloads match the stored records and both operations remain queued for future sync. SQLite integrity passed with no foreign-key errors. No phone data was changed, and no database snapshot, credentials or actual coordinates are included in the repository.
- One phone record had no peers and the other had one. Multiple-peer persistence is covered by automated tests; these phone records did not exercise multiple peers.

## Password visibility update (0.2.1+3)

- Added independent eye toggles for registration Password/Confirm password and sign-in Password. Typed text is retained when toggling; fields start hidden.
- Code analysis passed. All four widget tests passed, including visibility independence/text preservation and existing account/lock flows. Authentication/storage code was unchanged, so database/password-hashing tests were not rerun for this UI-only change.
- Debug APK built successfully (19.2 seconds) and installed as an update on the connected phone without clearing app data.

## Implemented

- Android-only Flutter project at the repository root; project documents in docs/.
- ANSVK Outreach themed development preview, replacing the generated counter demo.
- App version 0.1.0+1; provisional application ID org.ansvk.ansvk_outreach.
- Android app label configured; manifest backup flag disabled.
- Launch smoke test and developer README.

## Verification

- Flutter 3.44.1, Dart 3.12.1, Java 17, Android SDK 36.0.0.
- Flutter doctor: no issues; Android licenses accepted.
- Package resolution: passed; pubspec.lock records resolved versions.
- Formatting: completed.
- Flutter analyze: no issues.
- Flutter test: 1 launch test passed.
- Debug APK build: passed (232.1 seconds). Output: build/app/outputs/flutter-apk/app-debug.apk.
- Physical Android device: model 24129RT7CC running Android 16. USB installation succeeded; cold launch returned Status: ok (1507 ms). App remained the foreground activity, and its preview screenshot was visually checked with no clipping observed. The running app's filtered Flutter/AndroidRuntime error log returned no entries during this check. Screenshot: build/device_checks/preview.png (local build artifact).
- This verifies scaffold installation and launch on one phone only; account, data-entry, offline persistence and lock behavior remain unimplemented and untested.

Local Flutter checks completed with NO_PROXY/no_proxy set to localhost,127.0.0.1,::1 for the command process. SDK cache access required execution outside the restricted workspace. No global proxy configuration was changed.

## Remaining foundation work

SQLite schema version 3, repository ownership rules, transactional audit/outbox writes, database summary queries, registration/login and locking are implemented; see 06_local_database.md and 07_accounts_and_lock.md. Database encryption/recovery remain foundation work. Production synchronization is not implemented. The development app must not be used for live outreach.

The generated release build still uses debug signing. Configure release signing before pilot distribution; a scaffold debug APK is not a production release.

## Database build verification

- Added sqflite 2.4.3, path and UUID dependencies; native SQLite test support is development-only.
- Code analysis: no issues. Tests: 9 database tests and 1 launch test passed.
- Debug APK rebuilt successfully in 56.8 seconds and installed over the preview on the connected Android 16 phone.
- Cold launch returned Status: ok (1826 ms). Running app's filtered Flutter/AndroidRuntime error log returned no entries.
- Confirmed app-private databases/ansvk_outreach.db exists on the phone (110592 bytes). Creation runs before the preview screen appears.
- Phone has no sqlite3 shell executable, so table contents were not queried directly on the phone. Schema, constraints and integrity were verified in the native SQLite tests on the computer.
- No sample client records were inserted on the phone. UI remains unchanged.

## Account build verification (0.2.0+2)

- Added cryptography 2.9.0 and additive credential migration 1 → 2.
- Code analysis: no issues. All 19 tests passed, including real production password hashing, account forms and the 60-second lock.
- Debug APK build passed (18.0 seconds). Installed as an update on the connected Android 16 phone without clearing app data.
- Cold launch: Status: ok, 1848 ms. App-specific Flutter/AndroidRuntime error log returned no entries.
- Device accessibility hierarchy confirms Create your account, username/password guidance and account actions are on screen. Secure-window protection intentionally blocks screenshots; no screenshot bypass was attempted.
- No account was created by the agent on the user's phone. Actual registration/unlock walkthrough is ready for the user; automated tests cover those flows on the development computer.
