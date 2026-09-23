## QR-only manual interface cleanup

- Removed manual address/code/fingerprint form and save/check/pair/clear controls on `codex/qr-pairing-apk`. Kept reusable security, pairing, database and sync services. New enrollment awaits the QR scanner; existing connection data is unchanged.
- 27 focused UI/pairing/QR tests passed; analysis clean. Local source checkpoint saved; no commit, push, phone installation or LAN edit. See `37_manual_pairing_cleanup.md`.

## One-phone synthetic test APK installed

- Corrected artifact installed after USB reconnect: exact checksum/native flag verified, signed0.9.9+24 update succeeded and launched. Records preserved by update; no uninstall/storage clearing. Owner private export is next. See `35_one_phone_manual_test_action.md` for final checksum and exact status.

- Signed0.9.9+24 installed as an update and launched. Test-only frozen review export/manual one-batch action enabled; ordinary builds remain disabled. 12 focused default/export checks and one enabled-export check passed; analysis clean. LAN private driver reports nine tests/lint passed and is ready for exact private review/explicit approval.
- Await phone prepare/private USB export to obtain original identity; no phone upload, phone-facing listener or firewall change. See `35_one_phone_manual_test_action.md`.

## Actual APK/restricted successor integration

- Both actual loopback end-to-end scenarios passed. Restricted mode rejects preapproval/changed bytes/later batch, accepts exact frozen reviewed creates and identical replay, preserves unaccepted revisions, and verifies exact backend operation/payload matches and daily backup. U1 regression remains passed; focused analysis clean.
- No phone build/install/window/firewall/upload changes. Private manifest handoff/launch driver and appropriate test APK remain preparation work. See `34_restricted_dashboard_apk_integration.md`.

## One-phone restricted dashboard implementation

- LAN reports separate successor local implementation/tests complete (4 files/13 tests + lint). Independently reviewed admission/source/auth/hash/backup/expiry checks and verified six hashes; 13 local guard/regression tests passed. Actual APK-to-successor test remains next. No phone-facing driver/window enabled. See `33_one_phone_test_preparation.md`.

- Owner authorized bounded separate successor implementation/local loopback tests, dispatched to LAN PM. Requires exact approved source/identity/raw+canonical batch hashes/tuples, expiry, normal auth and verified backups; results pending. No live window/firewall/phone update/upload enabled. See `33_one_phone_test_preparation.md`.

## Frozen reviewed-batch safeguard

- Review UI now holds a memory-only frozen plan. Configured reviewed runs send exact bytes, enforce one batch and invalidate if the pending snapshot/identity changes. Refresh/reprepare/lock/disposal discard the plan. No upload UI or phone update enabled.
- All 28 focused UI/configured-service/runner/actual-LAN tests passed; focused analysis clean. Owner confirmed all phone pending worker records are test data; exact outbound review remains required. Home addresses checked: laptop 192.168.1.7, phone 192.168.1.4 (point-in-time). No network settings changed. See `32_frozen_reviewed_batch.md`.

## APK-to-actual-LAN loopback integration

- LAN final timestamp regression report received: 4 files/51 tests and lint passed. Updated validator/worker hashes independently verified; pending regression evidence resolved. No additional phone changes.

- One actual end-to-end test passed: normal synthetic enrollment, pinned Dart transport/configured runner, 3 creates, duplicate replay, 2 update/delete revisions, empty status, exact durable operation/payload matches and verified daily backup. Focused Dart analysis clean. Test-only tools added; no phone modifications.
- Discovered LAN timestamp precision rejection; LAN PM updated validation to accept preserved six-digit UTC fractions. Actual microsecond integration passes; LAN's standalone validator regression report remains pending after its task usage limit. See `31_apk_lan_loopback_integration.md`.

## U2 phone review build 0.9.8+23

- Owner reported the requested no-send phone walkthrough passed: batch/operation review works, record labels and pending count are correct, and Refresh clears review. This is user-reported phone acceptance; no live upload is claimed.

- All 25 focused manifest/workspace/pairing tests passed, focused Dart analysis clean. Signed Gradle release build passed in 5 minutes; apksigner verification and AAPT package/version/INTERNET checks passed.
- APK `build/app/outputs/flutter-apk/app-release.apk`: 66,910,922 bytes; SHA-256 `4B3C82CA65C6AED118D7090E245E70596306F38D41D156008794A5ED12AFF4B6`.
- Installed with `adb install -r` on ORCE49UWDQVGRC49 without clearing storage. Package reports version 0.9.8/build 23; cold launch Status ok, 802 ms. User review pending. No uploads, retention, pairing reset or phone records/outbox modifications performed.

## U2 local no-send first-batch review

- Added an expandable local review with exact batch/operation identity, record labels, revisions/sequences and body/payload hashes. First-batch dependency warnings require dashboard confirmation; test-data status remains explicitly unverified. Refresh clears review; queue unchanged.
- All 13 focused manifest/workspace tests passed; focused analysis clean. No upload action, release build/install or phone changes. See `30_no_send_batch_review.md`.

## Controlled upload planning

- LAN U1 backend evidence received/reviewed: LAN reports lint and 2 files/3 scenarios passed; independently checked tool hashes, loopback isolation/backup wiring and all 16 contract fixtures. Ten local guard tests passed. Reviewed upload guard snapshot retained; S3 unchanged. No phone-facing listener or upload authorized. See `29_controlled_upload_test_plan.md`.

- U1 successor implementation/loopback synthetic enrollment/auth/storage/backup tests authorized and dispatched to LAN PM; evidence pending. APK one-batch run limit implemented and verified with 13 focused tests and clean analysis. No phone UI/build/install/upload changes.

- Drafted `29_controlled_upload_test_plan.md` and incorporated LAN PM read-only review. Requires a separate fresh-store successor, normal authentication, actual verified backup behavior, outbound manifest and enforced one-batch first phone test. Implementation/evidence pending; no dashboard readiness is claimed.
- Planned laptop-only actual API testing before phone UI/upload testing. The entire selected worker queue must be confirmed synthetic, because the runner sends all its pending operations. No service/firewall/build/install/upload changes performed.

## Configured manual sync integration

- Connected secure upload/status transport to the runner through a configuration/session guarded service. Authenticated status is checked before upload and for empty queues. Status never acknowledges operations.
- All 19 focused configured-service/runner/transport/real-TLS tests passed; focused analysis is clean. No UI enablement, phone build/install/data changes, retries, completion timestamp or retention. See `28_configured_manual_sync.md`.

## Local HTTPS integration and status validation

- Concrete loopback TLS tests passed for UTF-8 uploads, chunked replies, status GET, wrong certificate blocking, redirects, malformed JSON and response limits. Added exact device/worker active-status validation; status watermarks cannot acknowledge operations.
- All 12 focused HTTPS/status/transport tests passed; focused analysis is clean. Temporary test keys deleted and test servers closed. No build/install or phone data changes. See `27_secure_sync_transport.md`.

## Secure sync transport preparation

- Added certificate-pinned upload/status transport with secure-store Bearer authentication, same-socket certificate verification, timeout, response/upload bounds and redirect refusal. Not connected to UI or the runner.
- All 15 focused transport/runner/SQLite tests passed. Transport security tests use injected connections; concrete local TLS integration and status validation remain next. No build/install or phone data changes. See `27_secure_sync_transport.md`.

## Manual sync orchestration with fake transport

- Added sequential batch orchestration with exact receipt application, partial/failure stops, concurrent-run guard and session checks. No concrete transport or UI integration is enabled; empty queues do not claim dashboard success.
- Nine focused runner/SQLite tests passed. No phone build/install or data changes. See `26_manual_sync_orchestration.md`.

## P2.5b local SQLite acknowledgement application

- Added transactional exact-operation acknowledgement application, with worker/project/device and full audit snapshot validation. Rejected/missing operations and newer revisions remain pending; duplicate application is idempotent. No UI/transport connection, retention or whole-sync completion marking is enabled.
- All 38 focused sync/database tests passed. No schema change, release build, phone installation or phone data modifications occurred. See `25_offline_acknowledgement_validation.md`.

## P2.5a offline acknowledgement validation

- Added exact-batch receipt validation with immutable accepted/rejected/missing operation results. Unknown, repeated, mismatched or malformed entries invalidate the receipt. No database marking, transport, cleanup or phone installation is enabled.
- All 24 focused acknowledgement/batch tests passed; focused Dart analysis is clean. Updated API receipt examples to match accepted fixtures and the LAN implementation. See `25_offline_acknowledgement_validation.md`.

## Local preparation phone review build (0.9.7+22)

- User reported the requested offline phone walkthrough passed: local validation/counts work with connectivity off, pending changes remain unchanged, paired state remains Yes, Ready to sync remains No, and Refresh clears preparation results. No live upload or acknowledgement is claimed.
- Updated app/request/preparation version to 0.9.7+22. All 30 focused widget, batch and pairing tests passed; focused Dart analysis is clean. Signed Gradle release build completed successfully; APK signature verification and AAPT version/INTERNET checks passed.
- Artifact: `build/app/outputs/flutter-apk/app-release.apk`, size 66,845,386 bytes, SHA-256 `34FBF72DAF3FA5D7E0355A05D8B2B49A39A4FB09448C1EB9A2B3B6929D209B20`.
- Phone temporarily disappeared before installation, then reconnected. Installed as an update with data preserved; physical package reports 0.9.7/build 22 and granted INTERNET permission. Cold launch succeeded. User offline preparation/count/pairing-preservation walkthrough remains pending. No network upload/acknowledgement/cleanup is enabled.

## P2.4b local preparation action in Sync Status

- Added Prepare changes locally with current worker's operation count, batch count and total bytes; clear success/empty/failure results. No payload content or raw parsing exception is shown, and no credential/network/SQLite write is used for preparation. Refresh resets the previous result; navigation/worker changes discard late results.
- Updated connection wording to reflect the actual paired state and disabled sending. All 18 focused widget/builder tests passed, including queue preservation, refresh, empty and malformed payload cases; focused Dart analysis is clean.
- No phone review build/install or APK version change was performed. Next is a signed phone review test; upload/acknowledgement/cleanup remain disabled. See `24_offline_sync_batch_preparation.md`.

## P2.4a offline sync batch preparation

- Added a pure v1 batch builder with ownership/identity/revision checks, decoded payloads, ordered immutable batches and 100-operation/1-MiB UTF-8 limits. Individually oversized operations block preparation without skipping dependencies; empty queues produce no batches.
- Eight focused tests passed, including four exact accepted fixtures and actual SQLite queue preservation. Focused Dart analysis is clean. See `24_offline_sync_batch_preparation.md`.
- No UI integration, network upload, credential use, acknowledgement, cleanup, APK version change/build/install or phone data changes occurred.

## S3 pairing and APK restart passed (0.9.6+21)

- Owner reported all requested Wi-Fi-only retry steps passed: certificate matches, actual pairing succeeds, and after APK restart Dashboard paired remains Yes with Ready to sync No. This is user-reported phone acceptance, not backend restart persistence.
- Independent read-only inspection of the final isolated dashboard found exactly one active device, one used pairing code, zero accepted operations and zero sync batches. Server metadata recorded HTTP 201/paired. No upload, acknowledgement or retention cleanup was performed.
- Stopped the exact test service and verified no LISTENING rows remained on ports 3001 or 3443. Protected synthetic stores retained. Owner removal of temporary firewall rule `Outreach-S3-Retry` remains pending, so rollback is not fully closed yet.
- Next proposed development chunk is offline sync payload/batch preparation against the accepted API contract, with no real upload/acknowledgement/cleanup activation.

## Pairing fix installation and fresh S3 retry setup

- Wi-Fi-only follow-up: owner disconnected Ethernet. Verified laptop Wi-Fi 192.168.1.100 and phone 192.168.1.11; previous listeners were already absent. Generated a fresh protected SAN-valid certificate for .100 and started a new isolated S3 instance. Phone TCP reachability now passed; trusted local TLS/upload-403 and unauthenticated code-401 checks passed. Phone certificate/pairing/restart results remain pending. Existing temporary S3 firewall rule still targets .2 and must be removed at test closure.
- Firewall inspection correction: `netsh ... show rule name=` matches the display name, not PowerShell's internal rule Name. Earlier missing-rule assertions based on internal names were unreliable. Display-name inspection confirmed the S3 retry rule exists with the requested restricted .2/.11/Private settings; S1 display-name inspection found no matching rule. No further rule was created by the agent.
- Owner reauthorized build/install after the declined request. Following interruption, verified the completed release artifact using AAPT (0.9.6+21, INTERNET permission) and APK signature verification; installed as an update preserving data. Physical package version and granted INTERNET permission confirmed, cold launch successful.
- Artifact size 66,747,082 bytes; SHA-256 `F6FD354FFD59704EC37A28EDF6CA49B4CBE4A3303AC96D28A545F2DADA588239`.
- Laptop DHCP address changed to 192.168.1.2, so generated a new protected short-lived synthetic certificate covering that address, then started a fresh isolated S3 store. Old state retained. Operator address remains loopback 3001/operator; new phone API is https://192.168.1.2:3443/api/v1. No code generated or phone pairing attempted by the agent.
- Phone was USB-connected but had no wlan0 IPv4 at initial check; requested same-network Wi-Fi connection. Owner must explicitly clear only saved pairing after install, enter the newly displayed trusted fingerprint/address and generate a fresh code. Uploads/acknowledgement/cleanup remain excluded.

## Pairing state protection fix (0.9.6+21 development)

- S3 phone inspection showed Dashboard paired No and pairing code saved Yes, while read-only dashboard SQLite showed one active device and one used code. Test service metadata logs later confirmed a successful 201 pairing followed by a 409 pairing_code_used retry. Saving preparation before that retry reset the local paired row; no upload occurred.
- Saving identical dashboard settings now preserves a Paired row; changing a paired dashboard is rejected. Paired UI locks address/code/fingerprint and disables save/re-pair. The pairing service also blocks repeat attempts before any network call. Explicit Clear saved pairing now removes the hidden device credential as well as local settings/fingerprint.
- All 29 focused pairing/widget/database tests passed after the final changes; focused Dart analysis found no issues. Regression coverage includes paired metadata survival after settings-save/database reopen, rejection of dashboard changes, no repeat transport call, locked paired controls and credential deletion on explicit clear.
- Signed build execution was rejected at the permission gate. No 0.9.6+21 APK was built or installed; phone remains 0.9.5+20. Stopped the previous synthetic dashboard instance and confirmed test listeners gone; old isolated state is retained.
- LAN PM confirmed retry requires a fresh empty synthetic dashboard store, because the existing device and used code conflict in the old store. After build/install, owner explicitly clears only pairing settings/credential, recreates a synthetic admin on a fresh instance and uses a new code with unchanged phone worker/device identity. Phone records/outbox are not cleared. This is a synthetic workaround, not production lost-response recovery or backend restart persistence.

## S3 preparation: pairing-only request guard

- Owner approved LAN PM coordination for isolated launcher integration. Sent the guard and preparation document for review against actual LAN authorization/storage. Subsequent read-only checks found no S1 firewall rule by its exact name and no listener on 3443; earlier pending rollback checks are now closed. No firewall changes were made in this check.
- Added local synthetic test guard and five passing HTTP tests; uploads and browser actions outside pairing preparation are blocked before supplied backend handlers. Allowed requests preserve backend responses; actual LAN authorization/storage integration remains pending.
- See `23_s3_pairing_test_preparation.md` for scope, evidence limits and the next isolated launcher chunk. No live server, code issuance, pairing or phone data change occurred during this preparation chunk.

## Release network permission fix (0.9.5+20)

- User reported both certificate checks worked and pairing preparation settings were saved. Correct/wrong fingerprint phone checks are accepted; successful dashboard pairing is not claimed. Stopped the isolated Node test service and confirmed no TCP listener remained on 3443. Administrator removal of temporary firewall rule `Outreach-S1-62f431de` remains pending; S1 rollback is not fully closed until that is confirmed.
- Diagnosed the S1 phone connection failure: installed release 0.9.4+19 lacked `android.permission.INTERNET`; only the debug manifest declared it. Added the permission to the main manifest for release builds.
- Updated app and pairing request version to 0.9.5+20. Focused pairing/certificate tests passed (16 tests); signed Gradle release build passed. AAPT inspection of the final APK confirms versionCode 20/versionName 0.9.5 and INTERNET permission.
- Release SHA-256: `FC3CE4E3833996112DB94CC32318E8CDCD03617E4F56CF873415F361424D2955`. Installed with update flag on the connected phone, preserving app data. Certificate match/mismatch retest remains pending; no pairing, upload, acknowledgement or cleanup was performed.

## Development laptop S1 preparation (2026-09-17)

- User authorized isolated laptop certificate-test setup. Started the existing LAN Outreach server module with fresh synthetic SQLite/TLS/backup paths under an ignored, uniquely named `build/s1-*` directory with restricted folder ACLs; no production environment file was loaded.
- Endpoint: `https://192.168.1.5:3443/api/v1`; selected phone Wi-Fi address: `192.168.1.3`. A seven-day self-signed certificate covers the laptop IP. Local TLS verification using that certificate as the explicit trust source passed; its DER SHA-256 matches the locally generated public fingerprint.
- The local test launcher replaces HTTP request handlers with a 403 response; only TLS certificate checking is available, preventing pairing and upload during S1. No APK source change or phone installation was needed.
- Attempt to create a phone-restricted temporary firewall rule failed with Windows Access Denied, even outside the sandbox; no successful firewall change is claimed. A phone TCP reachability probe completed with exit code 0. APK correct/wrong fingerprint checks and final stop/rollback remain pending user testing.
- This is development S1 setup evidence only, not S1 acceptance, successful pairing, sync or office deployment approval. Local test artifacts and private key remain excluded from Git.

## APK review build 0.9.4+19

- User reported the requested phone UI walkthrough passed on 2026-09-17. This records acceptance of the pairing UI review only; it does not establish a successful live certificate check or dashboard pairing.
- Bumped the APK version to `0.9.4+19` for a phone review build containing the controlled **Pair with dashboard** UI action.
- Focused validation completed on the development computer: pairing and hotspot widget tests passed with `flutter test test\pairing_preparation_test.dart test\hotspot_widget_test.dart --concurrency=1`.
- Release APK built successfully through Gradle after refreshing generated Flutter version metadata in `android\local.properties`. The Flutter wrapper build command hung before starting; direct Gradle build required access to the existing `D:\gradle` cache.
- Release artifact: `build\app\outputs\flutter-apk\app-release.apk`; size 66,681,502 bytes; SHA-256 `99EC146D5651E9445F6168DFE87FBB4B249F0F33187A5BE1D50F786E58282D2D`.
- Installed over the existing release app on phone `ORCE49UWDQVGRC49` with app data preserved. Installed package reports `versionName=0.9.4` and `versionCode=19`.
- Cold launch put `org.ansvk.ansvk_outreach/.MainActivity` in the foreground. A recent log sample showed no AndroidRuntime/FATAL exception for the app.
- This phone install did not connect to the office LAN dashboard, pair with a real dashboard, upload records, acknowledge operations, enable Ready to sync, or run retention cleanup.
## S2 pairing UI wiring

- Added a controlled **Pair with dashboard** action to the Dashboard Pairing screen. The action saves the entered HTTPS `/api/v1` address, six-digit pairing code and approved certificate fingerprint, then uses the certificate-pinned pairing service.
- The pairing action returns to Sync Status after a verified success so the worker can see the dashboard is `Paired`. **Ready to sync** remains `No` because upload, acknowledgement and cleanup are still disabled.
- Added test injection for the pairing transport and an explicit in-memory device-credential store for widget tests. Production still uses secure storage for the hidden dashboard device credential.
- The saved pairing code is not shown again when reopening the pairing screen. The worker must re-enter the code before pairing if the screen was reopened.
- This chunk does not install on phone, connect to office LAN, upload records, acknowledge operations, enable sync, or clean retention data.
- Validation completed on the development computer: focused UI test passed with `flutter test test\hotspot_widget_test.dart --concurrency=1`; full Flutter tests passed with `flutter test --concurrency=1`; full Dart analysis returned no issues.
## S2 pairing engine core

- Added `DashboardPairingService` for the future live pairing action. It builds the v1 pairing request from the existing APK app identity, current worker profile and saved six-digit pairing code.
- Added a certificate-pinned HTTPS pairing transport. The transport verifies the server certificate SHA-256 fingerprint on the same connection before sending the pairing request, so a separate earlier certificate check is not treated as enough trust by itself.
- Added repository support to apply only a verified pairing success: the hidden device credential is stored in secure storage, the dashboard row is marked `Paired`, and the pairing code is cleared only after the credential and paired state are safely saved.
- Safe failure behavior is covered: rejected codes, certificate mismatch/blocked transport and mismatched device responses do not store credentials, do not mark the dashboard paired, and keep the pairing code available for retry.
- This chunk does not add a UI pairing button, phone install, office LAN connection, sync upload, operation acknowledgement, retention cleanup or real data handling.
- Validation completed on the development computer: focused pairing tests passed with `flutter test test\pairing_preparation_test.dart --concurrency=1`; full Flutter tests passed with `flutter test --concurrency=1`; focused Dart analysis of the changed files returned no issues.
# Scaffold build status

## P2.3b offline pairing response parsing

- Added an offline pairing response parser for the accepted v1 success and error response shapes.
- The parser validates that a success response belongs to this device and this worker before any future code could store the device credential or mark the phone paired.
- Known pairing error codes are mapped to worker-facing messages for later UI use.
- Validation completed on the development computer: focused pairing preparation tests passed with `flutter test test\pairing_preparation_test.dart --concurrency=1`.
- No network request, live pairing, credential storage from a response, dashboard state update, pairing-code deletion, sync enablement, release build, phone install, push or real data was performed for this P2.3b chunk.

## APK review build 0.9.3+18

- Bumped the APK version to `0.9.3+18` for a review/test build containing P2.2 certificate checking plus P2.3a/P2.3b offline pairing preparation.
- Validation completed on the development computer: `flutter analyze --no-pub` passed and full Flutter tests passed with `flutter test --concurrency=1` showing 47/47 tests.
- Release-signed APK built successfully from the private signing configuration. Output: `build\app\outputs\flutter-apk\app-release.apk`; size 65,965,198 bytes; SHA-256 `413E24677AAAEB4D4EFF50DF29A0755907F28E8DB2D74FEBA5F82451832DD484`.
- Phone install over existing test data succeeded on device `ORCE49UWDQVGRC49` with versionName `0.9.3` and versionCode `18`. The app launched with no immediate Flutter/AndroidRuntime crash in the short log check.
- User phone walkthrough passed: existing data remained usable, Sync Status opened, Dashboard pairing preparation opened, certificate-check action was visible, validation behaved as expected, and real sync remained disabled.
- No LAN pairing, network sync, upload, acknowledgement, cleanup, push or real data was performed for this review build.

## P2.3a offline pairing request preparation

- Limited P2.3a work was performed after the user's later "proceed" instruction. This is offline preparation only; live P2.3 pairing remains gated on LAN readiness.
- Added a pairing request builder that creates the accepted v1 `POST /api/v1/pairing/requests` JSON shape from app identity, signed-in worker profile, six-digit pairing code, app version and UTC request time.
- Added a secure-storage device credential holder for the future dashboard credential. The credential is not stored in SQLite and is not connected to any live pairing response yet.
- Added a repository helper that exposes only signed-in worker profile fields needed for future pairing. It does not expose password verifier material.
- Validation completed on the development computer: pairing preparation and database tests passed with `flutter test test\pairing_preparation_test.dart test\database_test.dart --concurrency=1`.
- No network request, dashboard connection, pairing response handling, dashboard state update, pairing-code deletion, sync enablement, release build, phone install, push or real data was performed for this P2.3a chunk.

## P2.2 certificate fingerprint checking

- Limited P2.2 authorization was granted by the user's "can we proceed?" instruction after P2.1 passed. Only HTTPS certificate fingerprint checking was authorized; P2.3-P2.8 remain unauthorized.
- Added a dashboard certificate checker that opens a TLS connection to the saved HTTPS dashboard address, reads the presented server certificate, computes its SHA-256 fingerprint, and compares it with the worker-entered approved fingerprint.
- The certificate check does not send a pairing request, sync request, client records, pending operations, acknowledgement state, worker password data, SQLCipher material, or device credential.
- Added a **Check certificate** action to the Dashboard pairing preparation screen. It reports match, mismatch, invalid address, invalid fingerprint, or unavailable dashboard. Saving pairing info remains separate and real sync remains disabled.
- The full approved fingerprint remains stored through secure storage from P2.1. SQLite schema remains version 6.
- Validation completed on the development computer: certificate checker and hotspot widget tests passed with `flutter test test\dashboard_certificate_checker_test.dart test\hotspot_widget_test.dart --concurrency=1`; full Flutter tests passed with `flutter test --concurrency=1`; static analysis passed with `flutter analyze --no-pub`.
- No phone install, real dashboard connection, pairing, upload, acknowledgement, cleanup, release build or push was performed for this P2.2 chunk.

## P2.1 sync configuration alignment

- Limited P2.1 authorization was granted after the user's "ok proceed" instruction and LAN PM review. Only sync configuration UI alignment was authorized at that time; P2.2 was authorized later as a separate certificate-checking chunk.
- Updated the Dashboard Pairing preparation screen to require an HTTPS device API address ending in `/api/v1`, such as `https://192.168.1.50:3443/api/v1`.
- Updated pairing-code validation to exactly six digits and preserve leading zeros.
- Added manual full certificate SHA-256 fingerprint entry and validation. The full approved fingerprint is stored through secure storage, not SQLite. Sync Status shows only a short fingerprint hint.
- At the P2.1 stage, the screen remained preparation-only and did not inspect the live certificate, send network requests, pair, upload, acknowledge, retry, enable cleanup, or report sync success. P2.2 later added a certificate-only check while keeping pairing, upload, acknowledgement and cleanup disabled.
- Clearing saved pairing clears the saved address/code and fingerprint trust value without deleting offline records, audit operations, pending outbox rows or app identity.
- Validation completed on the development computer: focused database and hotspot widget tests passed with `flutter test test\database_test.dart test\hotspot_widget_test.dart --concurrency=1`; full Flutter tests passed with `flutter test --concurrency=1`; static analysis passed with `flutter analyze --no-pub`.
- A debug APK built successfully but could not update the phone because the phone had a release-signed build installed.
- A release-signed P2.1 test APK then built successfully and installed over the existing release app on phone `ORCE49UWDQVGRC49`, preserving app data. Output: `build\app\outputs\flutter-apk\app-release.apk`; size 65,719,310 bytes; SHA-256 `1F913CA30A0A13BEC869BCB735E7631333B6593170C0077B7E6A0B1F02865F8F`.
- The user completed the manual P2.1 phone check and reported that the APK behaved as instructed: HTTPS/pairing-code/fingerprint preparation worked and sync remained preparation-only.
- No push, real LAN test, network pairing, upload, acknowledgement, cleanup or real data was performed for this P2.1 chunk.

## Pre-pilot readiness checklist

- Added `docs/17_pre_pilot_readiness.md` as the current review artifact for deciding whether the APK can move beyond development testing.
- The checklist separates development testing, possible local-only pilot before dashboard, and full pilot with dashboard sync.
- It records that release signing, all-phone dummy-data testing, worker training and dashboard sync remain open before full real-client deployment.
- Added `docs/18_release_signing_plan.md`, `android/key.properties.example` and a Gradle release-signing hook that reads private signing values from ignored local `android/key.properties`.
- Release builds no longer silently use the debug signing key when private release signing settings are absent.
- Validation: normal debug build still succeeds with the new Gradle signing hook. A general `gradlew tasks` listing still hits the known Flutter plugin cross-drive path issue in this environment, so it is not used as the project validation command.
- Release APK 0.9.2+17 built successfully from the private signing key on 15 September 2026. Output: `build\app\outputs\flutter-apk\app-release.apk`; SHA-256 `0F1DDB75304B0B2467C0DE1FC2EDF057DC1F0420C3F5B2D18B853D23176E76AB`.
- User manually installed the release APK without ADB and confirmed the phone test passed.

## Retention safety status (0.9.2+17)

- Added SQLite schema version 6 fields on `sync_state` for future retention-check and retention-cleanup timestamps.
- Added retention safety calculations to Sync Status. The APK now shows the 7-day keep window, old client-record count, old records held because they still have unacknowledged encounter operations, old records that would become eligible after acknowledgement, and cleanup enabled status.
- Cleanup remains disabled. This increment does not delete records, clear audit payloads, mark operations acknowledged or pretend that the dashboard has received data.
- Validation completed on the development computer: full Flutter test suite passed with `--concurrency=1`, and debug APK 0.9.2+17 built successfully. No phone install was performed for this increment.
- Phone install over existing test data succeeded on device `ORCE49UWDQVGRC49`. User phone walkthrough passed: existing data remained visible, Sync Status opened, Retention safety appeared, and cleanup remained disabled.

## Dashboard pairing preparation (0.9.1+16)

- Added SQLite schema version 5 fields on `dashboard_connection` for a locally saved future pairing code and pairing-prepared timestamp.
- Updated Sync Status to show address saved, pairing code saved, ready to request pairing, dashboard paired and ready to sync as separate checks.
- Updated the dashboard setup screen to save a local dashboard API address plus a pairing code. This prepares a later dashboard pairing request only; it does not contact the dashboard, upload data, acknowledge operations or clean up records. P2.1 later tightened this preparation field to exactly six digits.
- Validation completed on the development computer: full Flutter test suite passed with `--concurrency=1`, and debug APK 0.9.1+16 built successfully.
- Phone install over existing test data succeeded on device `ORCE49UWDQVGRC49`. User phone walkthrough passed: Dashboard pairing accepted a local dashboard address and pairing code, Sync Status showed address/code prepared, and real sync remained unavailable. Later LAN reconciliation found an Outreach dashboard foundation exists, but this APK version still had no live pairing, upload, acknowledgement or cleanup.

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

SQLite schema version 3, repository ownership rules, transactional audit/outbox writes, database summary queries, registration/login and locking are implemented; see 06_local_database.md and 07_accounts_and_lock.md. Database encryption/recovery remain foundation work. Production synchronization is not active. The development app must not be used for live outreach without explicit pilot approval.

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
