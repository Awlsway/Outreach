# Certificate Renewal in Normal Sync

Date: 2026-09-29
Status: Third APK renewal subchunk implemented and source/widget-tested.
Debug Android compilation and package inspection subsequently passed; see
[Android build evidence](47_certificate_renewal_android_build.md).
Signed release candidate 0.9.11+26 is now prepared and package/signature verified;
see [candidate evidence](48_certificate_renewal_signed_candidate.md).
Android provider/runtime, real camera, signed-APK installation and joint
LAN/phone renewal UAT remain pending.
The installed APK is unchanged.

## Worker Flow

1. A signed-in, already-paired worker opens Sync status.
2. Certificate renewal opens a page inside the existing session/lock shell.
3. Scan renewal QR opens the existing local camera scanner in callback mode.
   Reading and reviewing the signed QR does not send a network request.
4. Continue renewal revalidates the approval, then uses the durable claim and
   confirmation service implemented in subchunk 2.
5. Saved claim/confirmation progress shows Resume renewal. Stop preserves
   progress and records. Clear success/error text identifies the result.
6. After confirmation, Back returns to refreshed Sync status. Ordinary Sync
   uses the newly confirmed pin and its unchanged batch schema.

An unpaired worker still uses the existing dashboard pairing QR flow.
Renewal does not re-enroll a phone, replace its permanent credential, reset
identity, or clear records.

## Session and Recovery Safeguards

- No renewal route is pushed above the app's authentication/lock shell.
- Lock/background removes an unsubmitted review and embedded camera.
  Late callbacks/results cannot reuse that approval or mutate trust.
- The real session shell is used in widget tests, including unlock notifications
  whose availability changes without a further revision increment.
- Lock/Stop during an accepted intent preserves durable recovery state.
  Unlock rereads it; the worker explicitly resumes.
- Back navigation is blocked while a renewal action is running. Stop remains
  available; leaving/reopening after it settles preserves saved progress.
- Ordinary Sync is disabled for pending claim or confirmation. Unreadable
  retained renewal history cannot fall back to the old pairing pin.
- Saved confirmation-pending state may review an approved successor grant only
  under the existing lost-confirmation rules; a pending claim cannot be replaced.
- Initial-trust preparation is coalesced. Sync status waits for an in-flight
  startup check instead of racing the lifecycle gate.
- UI messages do not display raw QR/JWS values, secrets or raw exceptions.
  The scanner itself performs no credential or network operation.
- Existing pairing scanner defaults and accepted protocol messages are unchanged.

The Sync status pending-count display is now a compact row, avoiding the
single-tile overflow seen at narrow phone widths. Its underlying count is unchanged.

## Verification

Final affected regression run: **241 tests passed across 12 suites**, no failures.
This includes **17 new renewal UI tests** covering:

- Unpaired entry, scan/review cancellation and invalid/wrong-purpose QR.
- Successful review/renewal followed by ordinary Sync and exact acknowledgement
  under wire schema 6, using the successor pin.
- Both saved pending phases across leaving/reopening and widget remount.
- Stop during claim and confirmation, blocked Back and exact Resume.
- Lock during review/claim, authenticated unlock, background camera disposal and
  late scanner callbacks.
- Invalid receipt and missing authority: safe error, no reset, no unsafe Sync.
- 320- and 390-pixel recovery views at 1.8x text scale.

The other 11 suites cover QR/review/fixtures, transition service, initial trust,
ordinary Sync, pairing, secure transport, authentication shell and workspace
navigation. They are focused regressions, not a repeated full-project test run.

Command:

    flutter test --no-pub test/certificate_renewal_page_test.dart test/certificate_renewal_review_test.dart test/certificate_renewal_service_test.dart test/initial_certificate_trust_test.dart test/normal_sync_widget_test.dart test/configured_manual_sync_test.dart test/widget_test.dart test/hotspot_widget_test.dart test/qr_pairing_coordinator_test.dart test/secure_sync_transport_test.dart test/certificate_renewal_qr_test.dart test/certificate_renewal_fixture_test.dart --reporter expanded

The new UI test uses memory SQLite, synthetic records, disposable signing keys
and a controlled peer/scanner. It compares worker/identity/pairing, pending
operations, records, sync state, original bootstrap and credential before/after
non-Sync renewal paths. Successful ordinary Sync alone acknowledges its batch.
Real camera hardware and Android providers are not exercised by this harness.

Scoped static analysis of the nine affected source/test files has no errors or
warnings. One pre-existing informational null-aware-elements advisory remains
in an unrelated workspace block. All six shared renewal fixture files are
SHA-256-identical across LAN and Outreach. Both repositories pass git diff --check.

## Files

- `lib/sync/certificate_renewal_page.dart`
- `lib/sync/initial_certificate_trust.dart` (guarded state reader)
- `lib/sync/certificate_renewal_review.dart` (explicit cancel/back)
- `lib/sync/qr_pairing_scanner_page.dart` (optional embedded callback mode)
- `lib/hotspots/hotspot_workspace.dart` (internal navigation, Sync gating)
- `lib/sync/configured_manual_sync.dart` (safe renewal error message)
- `lib/app.dart` (optional test transport/scanner injection)
- `test/certificate_renewal_page_test.dart`
- `test/certificate_renewal_ui_test_support.dart`

## Next Step and Release Boundary

Debug Android compilation and packaged native certificate/scanner references,
then signed release candidate 0.9.11+26, are verified. Next coordinate authorized
synthetic LAN/phone renewal UAT, including real native provider/camera behavior:
ordinary Sync, claim/confirmation loss, app restart, Stop/lock and pending-data
preservation. Keep production activation, office deployment and USB packaging
pending until that evidence and the outstanding deployment checks are accepted.

No phone was connected, reset, re-paired, installed or updated in this subchunk.
No native certificate code, LAN server code, production certificate,
service/firewall, office configuration or USB package was changed.
No commit, push or deployment was performed.
