# Initial certificate trust — APK implementation checkpoint

29 September 2026. Local uncommitted implementation on `codex/synthetic-sync-uat-v1`. No APK build, signing, installation, office key provisioning, deployment, commit or push.

Follow-up: debug Android compilation and package inspection passed after the
normal Sync renewal integration. See
[Android build evidence](47_certificate_renewal_android_build.md).
This does not add release signing, installed-phone or office evidence.

## Implemented behavior

Local schema 8 adds one `initial_certificate_trust` record to the existing Android SQLCipher database. Wire sync schema stays 6. The record holds the paired context and public bootstrap proof, never the permanent device credential. Its states are `bootstrap_pending`, `confirmation_pending`, and `confirmed`.

Before the first authenticated bootstrap, save a durable identity/endpoint/approved-pin snapshot and a digest binding to the existing credential. Only the separate trust endpoint may use that initialization snapshot. A successful response must match project, dashboard, device, worker, endpoint and pin exactly, with strict generation, bootstrap ID, authority date/JWK/kid validation. Commit the public proof and confirmation-pending state atomically, then delete legacy secure-storage pin bytes best-effort. Subsequent attempts never read legacy pin bytes when a trust record exists, even if deletion failed or someone changes them.

`POST /api/v1/certificate-trust` uses the exact contract actions `bootstrap` and `confirm_bootstrap`. All secrets travel only after the same socket passes pin/date/typed-IP-SAN verification. The trust route has bounded strict UTF-8 JSON parsing with duplicate/escaped-key and lexical-integer rejection; existing pairing/sync readers and envelopes remain unchanged. Confirmation must name the exact saved bootstrap, authority, pin and generation. A missing/malformed/non-200 reply preserves pending proof and records; it does not invent confirmation.

Ordinary Sync and debug status require confirmed authoritative trust. Sync resumes pending setup under a process-wide lifecycle gate before sending status or batches. Startup/login, unlocking and opening Sync also attempt pending setup without consuming a new pairing code. Local recording remains available during failure. Sync/status context guards use the authoritative record and session revision, not a legacy-pin fallback. The same gate serializes app pairing, setup and Sync/status; overlapping calls fail busy rather than queue stale session work. Late responses after lock/unlock, background/session change, credential change, pairing change or trust-record change cannot save trust or acknowledge records.

Already-paired or trust-bearing phones reject enrollment before any legacy pin write. Pairing also checks the session/configuration immediately before its TLS send and before saving the issued credential/result. The existing credential remains in Android secure storage.

The development plaintext-to-SQLCipher import now preserves its original schema version so normal upgrades can create the new table. It does not stamp schema 8 onto an unupgraded export. Existing encrypted data upgrades normally from version 7; no identity/outbox recreation occurs.

## Focused evidence

- Initial-trust tests: authenticated full-context setup, exact confirmation, lost bootstrap/confirmation replies, actual file reopen/restart, version-7 upgrade, identity/pin/JWK/authority/confirmation rejection, session epoch and credential changes, live-certificate rejection before HTTP, corrupt committed proof/no fallback, ordinary Sync blocked before setup, lifecycle concurrency, strict raw JSON.
- Existing configured Sync tests use explicitly preconfirmed test-only records to isolate batch/retry/Stop/retention behavior. They preserve frozen bytes, acknowledgements and cleanup semantics. The existing Sync widget passes with its asynchronous wait updated for the new guards. Existing pairing tests verify already-paired rejection leaves pin/credential untouched.
- Real loopback TLS checks verify the trust POST route/body and strict raw response decoding using the production Java certificate parser on desktop JDK17. Authentication and transport regressions pass.
- `initial_trust_lan_integration_test.dart` launches LAN's `tools/initial_trust_uat/dart_bridge.mts`. It uses production `startOutreachDeviceServer`, protected disposable renewal authority, fresh database/backups and loopback-only `127.0.0.1:3443`. It performs real QR pairing, confirms LAN rejects status before setup with `certificate_trust_required`, runs production APK bootstrap/confirmation without seeded proof, checks LAN readiness, then ordinary Sync uploads two synthetic operations. Identity/credential/pending data remain unchanged through setup. Temporary processes/files are disposed.
- The older full/restricted upload harness tests still pass at the transport/ManualSyncRunner level. Those harnesses use ephemeral ports and lack mandatory initial setup; they do not prove initial trust. The new production-startup test supplies that evidence and covers ConfiguredManualSync instead.

Actual test commands (Flutter executable `D:/flutter/bin/flutter.bat`, all `test --no-pub`):

1. Initial trust, configured Sync, QR coordinator, ordinary Sync widget, database, renewal fixtures and QR fixture: 79 passed on the combined run, with the widget wait still failing. The corrected widget-only run passed 1/1. All 80 distinct checks were subsequently validated; no claim that the earlier combined command exited successfully.
2. `test/secure_sync_https_integration_test.dart test/secure_sync_transport_test.dart test/auth_test.dart test/pairing_preparation_test.dart`: 38 passed.
3. Updated legacy `test/lan_sync_end_to_end_test.dart`: 2 passed (the companion new test initially failed compilation due to duplicate local test variable; corrected).
4. `test/initial_trust_lan_integration_test.dart`: production-startup integration passed 1/1 after correction.

121 distinct relevant checks passed across these runs. Scoped analysis of changed trust/transport/auth/database and new integration/test files reports no issues; including HotspotWorkspace additionally reports only its pre-existing null-aware-elements information at its shifted line. `git diff --check` passes.

## Contract alignment and limitations

LAN corrected only synthetic authority expiry to exactly five calendar years: mirrored `device-messages.json` SHA-256 is `d501d8f3fc8e7e1106c7662aa40d369f275c17b66f1b5173ce874cbb4f9a9484`; checksum file mirrored unchanged. The fixed JWS, QR pairing and sync fixtures stay unchanged. LAN aligned initial error names/mapping with contract section 7; APK safely preserves state for every unsuccessful trust response. No remaining verified wire conflict was found.

This checkpoint does not implement renewal QR/JWS scanning, grants, claim receipts, activation/rollback, address migration or authority recovery. Existing six server-state fixture cases remain for later lifecycle chunks. No Android native build/linkage, SQLCipher provider on an installed phone, secure-storage integration or physical-device TLS/clock/session behavior was verified. Desktop FFI transactions and desktop JDK parsing are distinct evidence. Installed APK 0.9.10+25 predates these changes.

The production-startup integration needs the LAN checkout/dependencies, Node/tsx, Java/Javac, OpenSSL and free loopback port 3443. It fails if occupied and does not stop another service. Synthetic server startup in the test is not office deployment. The unrelated untracked `android/Kimi-Test.code-workspace` and earlier dirty certificate-validation/fixture changes were preserved. No background server should remain after test teardown.

References: LAN `docs/37_certificate_renewal_contract_v1.md`; Outreach `docs/41_certificate_validation.md`, `docs/42_certificate_renewal_fixture_checks.md`; `lib/sync/initial_certificate_trust.dart`, `trust_json.dart`, `lifecycle_gate.dart` and new initial-trust tests.
