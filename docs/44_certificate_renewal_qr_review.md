# Certificate Renewal QR Verification and Review

Date: 2026-09-29
Status: First APK renewal subchunk implemented and source-tested. The second
subchunk now implements durable claim/save/confirmation and restart recovery;
see [transition evidence](45_certificate_renewal_transition.md). Neither is
released as an Android APK or tested on a physical phone. The third subchunk
now integrates scanner/review/recovery into normal Sync inside the session/lock
shell; see [navigation evidence](46_certificate_renewal_sync_navigation.md).
The subsequent debug Android compilation/package check passed; see
[build evidence](47_certificate_renewal_android_build.md).
Release signing and actual phone runtime/UAT remain pending.

## Completed

- Production renewal QR verifier uses the accepted v1 prefix and exact JWS
  signing bytes. It verifies Ed25519 only against the authority saved by the
  authenticated initial-trust workflow; a QR cannot introduce another key.
- Strict UTF-8, canonical unpadded base64url, exact JSON fields, duplicate-key
  rejection, lexical integer bounds, and the 2048-byte QR limit are enforced.
- Dashboard, project, device, worker, endpoint, committed pin and generation
  must match saved state. Successor pin must differ and generation must increase;
  an approved direct generation leap is allowed.
- Five-minute QR lifetime and saved authority validity are rechecked after
  asynchronous cryptographic work. Invalid, expired, future-dated and wrong-
  identity QRs produce safe messages without disclosing QR/JWS contents.
- A read-only initial-trust reader obtains the saved authority and a binding to
  the current session, pairing, credential digest and committed trust record.
  It rejects missing/uncommitted trust, a locked worker, and corrupt authority.
  A committed initial proof with a lost confirmation reply remains readable;
  this does not acknowledge that confirmation or enable ordinary Sync.
- A mobile worker-review component shows office and paired identities, expiry,
  optional certificate fingerprints, Cancel and Continue renewal. Continue
  rechecks current trust before and after verification and prevents duplicate
  approval or callbacks after disposal.

Verification and review do not make network requests, transmit credentials,
change a pin, migrate the database, or delete records. Approval returns only a
validated grant to the durable transition coordinator implemented in subchunk 2.

## Files

- `lib/sync/certificate_renewal_qr.dart`
- `lib/sync/certificate_renewal_review.dart`
- `lib/sync/initial_certificate_trust.dart` (read-only renewal context)
- `test/certificate_renewal_qr_test_support.dart`
- `test/certificate_renewal_qr_test.dart`
- `test/certificate_renewal_review_test.dart`
- `test/initial_certificate_trust_test.dart` (read-only preservation checks)

## Verification Evidence

Final combined Flutter test run: **133 tests passed**, no failures:

    flutter test --no-pub test/certificate_renewal_qr_test.dart test/certificate_renewal_review_test.dart test/initial_certificate_trust_test.dart test/certificate_renewal_fixture_test.dart test/qr_pairing_coordinator_test.dart test/configured_manual_sync_test.dart test/normal_sync_widget_test.dart

Scoped Dart analysis on the seven changed source/test files: **No issues found**.

The run covers the production reader with the shared Node-signed vector,
authentic but invalid synthetic messages, altered signatures, untrusted keys,
unsafe endpoints, wrong identities, rollback, malformed encodings, expiry during
verification, stale sessions, cancellation, duplicate approval, and disposal.
Widget checks exercised 320- and 390-pixel phone widths with 1.8x text scaling.
Read-only context checks preserve credential, identity, trust record and pending
operations. Existing pairing and normal Sync checks passed.

All six renewal fixture files were compared using SHA-256 with
`D:\LAN\docs\fixtures\outreach\certificate-renewal-v1`; every file is identical.
Fixtures and accepted pairing/sync messages were not changed. Disposable test
signing keys stay in memory and are not provisioned on a server.

## Next Subchunks

1. Durable intent, successor TLS checks, atomic claim receipt, idempotent
   confirmation, interrupted recovery and Sync gating are implemented and
   source-tested in subchunk 2. See the separate transition evidence.
2. Scanner/review integration inside the existing session/lock shell, explicit
   resume/Stop/result controls and focused navigation tests are implemented
   and source-tested in subchunk 3. No unguarded renewal root route was added.
3. Verify the Android build/provider, prepare the signed test APK, then run
   coordinated synthetic phone UAT for renewal and recovery without clearing
   enrollment or pending records.

The review is now reachable from normal Sync in source. The installed APK
predates the changes. Source/widget tests are not Android build, real camera,
joint renewal or release evidence.

No production certificates, Windows services, firewall rules, USB packages,
paired phones, or office installations were changed. No commit/push or deployment
was performed. No USB-debug phone is required for these source/widget tests.
