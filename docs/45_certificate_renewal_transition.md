# Durable Certificate Renewal Transition

Date: 2026-09-29
Status: Second APK renewal subchunk implemented and source-tested. Scanner,
normal Sync navigation and recovery controls are now integrated and widget-tested
in subchunk 3; see [navigation evidence](46_certificate_renewal_sync_navigation.md).
No Android APK was built or installed during this second subchunk, and no
physical-phone or office renewal was run. Subsequent debug compilation and
package inspection passed; see [build evidence](47_certificate_renewal_android_build.md).
Release signing and actual phone runtime/UAT remain pending.

## Completed

- Encrypted SQLite storage schema 9 adds retained renewal history. Storage
  versions 7/8 upgrade without resetting workers, pairing, records, queued
  operations or initial trust. Sync wire schema remains 6.
- After worker approval, the service rechecks the signed QR against the current
  saved authority, identity, session and trust. It stores a verified claim intent
  before opening TLS. A fresh expired scan cannot become an accepted intent.
- Claim and confirmation use the accepted fixed endpoints and exact bodies,
  with the existing permanent device credential. The actual successor
  connection must match the signed leaf pin, current validity and exact office
  IPv4 SAN before credentials or request bodies are sent.
- Lifecycle replies use bounded strict JSON, including the existing error
  envelope's details array. Duplicate keys, noninteger number tokens, malformed
  arrays and oversized replies are rejected.
- A complete matching claim receipt atomically commits successor trust and
  confirmation-pending state. The effective pin/generation is derived from
  validated retained receipt history, not a second mutable pin store.
- Only the exact successful confirmation clears pending state. Ordinary Sync
  stays blocked while a claim or confirmation is unresolved, before status,
  batch upload, acknowledgement or retention cleanup.
- SQLite constraints and triggers retain original signed proofs, receipts and
  confirmations and prevent overwriting or deleting saved lifecycle evidence.
- One lifecycle gate serializes renewal with pairing, Sync and other guarded
  operations. Session, worker, pairing and credential digests are rechecked at
  network/mutation boundaries; late replies after Stop or a session change
  cannot commit trust.
- Fixed a shared Stop race: an already-started asynchronous action must remain
  observed after cancellation, so a late TLS failure cannot become an unhandled
  exception. Ordinary Sync cancellation regressions pass.

The original authenticated bootstrap proof remains unchanged. Renewal does not
reset device identity, modify the permanent credential, clear pending records,
change service payloads or silently re-pair a phone.

## Supported Interrupted Recovery

| Situation | Retained state and next action |
| --- | --- |
| Lost claim reply or process restart | Retain the exact verified intent; resume against the same authorized successor and recover the identical receipt. |
| QR expires after a saved claim intent | Retry the saved intent only; a newly scanned expired QR remains invalid. |
| Authenticated expiry/cancellation of an unused grant | Mark only that intent rejected; preserve its signed proof and unchanged committed trust. |
| Uncertain network/HTTP error or invalid receipt | Keep claim pending; do not infer cancellation or change the pin. |
| Lost confirmation reply or restart | Keep committed successor pin/receipt pending; retry the exact confirmation without another claim. |
| LAN accepted an older confirmation but its reply was lost | A fresh grant from that committed state is possible; mark older retry superseded only in the same transaction as a matching new receipt. Retain all older proof. |
| Credential, worker, session or storage failure | Pause without clearing credentials or records; resume only with the correct restored context. |

Recovery revalidates an already stored grant at its saved verification time.
The saved authority must still be valid now, and each live successor connection
must still pass current certificate checks. There is no expiry bypass for a new
scan, fallback to an unknown certificate, key replacement via QR, or automatic
re-enrollment. Missing/expired authority or an unavailable approved successor
requires staff recovery outside the supported automatic v1 path.

## Verification Evidence

Final focused runs passed **236 tests across 13 suites**, with no failures:

1. **98 checks**: renewal service, secure transport/cancellation, initial trust,
   and retention migration.
2. **138 checks**: actual local TLS transport, database, authentication, renewal
   QR/review/fixtures, QR pairing, configured manual Sync, and normal Sync UI.

Commands:

    flutter test --no-pub test/certificate_renewal_service_test.dart test/secure_sync_transport_test.dart test/initial_certificate_trust_test.dart test/retention_migration_test.dart --reporter expanded

    flutter test --no-pub test/secure_sync_https_integration_test.dart test/database_test.dart test/auth_test.dart test/certificate_renewal_qr_test.dart test/certificate_renewal_review_test.dart test/certificate_renewal_fixture_test.dart test/qr_pairing_coordinator_test.dart test/configured_manual_sync_test.dart test/normal_sync_widget_test.dart --reporter expanded

Scoped Dart analysis of all 14 affected source/test files: **No issues found**.

The service tests use disposable signing keys, synthetic enrolled identity,
temporary SQLite and a controlled simulated LAN peer. They exercise every
receipt field, confirmation mismatch, definite unused rejection versus unknown
HTTP outcomes, successor pin/date/SAN failure, lock/Stop, migration, durable
restart, secure-storage errors, SQL commit failure and next-grant atomicity.
Preservation assertions compare workers, identity, pairing, hotspots, encounters,
audit operations, outbox, confirmations, Sync state, original bootstrap proof
and the unchanged device credential.

The separate TLS integration suite uses temporary certificates and the actual
socket transport/production Java certificate parser. It checks the renewal
paths, fixed POST bodies, credential transmission only on approved TLS, and
strict reply parsing. This is not joint renewal testing against a running LAN
backend, Android provider/build evidence, or physical-device UAT.

## Files In This Subchunk

- `lib/sync/certificate_renewal_service.dart`
- `lib/sync/certificate_renewal_state.dart`
- `lib/sync/certificate_renewal_qr.dart` (safe errors/context copy)
- `lib/sync/initial_certificate_trust.dart` (retained-history authority)
- `lib/sync/trust_json.dart` (strict error arrays)
- `lib/sync/secure_sync_transport.dart` (accepted renewal routes)
- `lib/sync/sync_run_control.dart` (late-error cancellation fix)
- `lib/database/app_database.dart` and `lib/database/schema.dart`
- `test/certificate_renewal_service_test.dart`
- `test/initial_certificate_trust_test.dart`
- `test/retention_migration_test.dart`
- `test/secure_sync_transport_test.dart`
- `test/secure_sync_https_integration_test.dart`

## Navigation Follow-Up

The existing QR scanner and worker review now call this service from an internal
page inside the normal worker session/lock shell. Resume/Stop/success/error
controls and saved-progress recovery are integrated. See subchunk 3 for the
focused widget and affected regression evidence.

Debug Android compilation/package inspection is now verified. Next prepare a
signed test candidate and run Android provider/camera checks and coordinated
synthetic LAN/phone renewal and failure/retry UAT. A USB-debug phone was not
needed for the completed source/widget and build-only subchunks.

No production certificate, service, firewall, USB package, enrolled phone or
office installation was changed. No commit, push or deployment was performed.
