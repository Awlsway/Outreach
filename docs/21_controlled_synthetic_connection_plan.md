> Historical development record: manual pairing UI has been removed. Current onboarding is QR-only; see `36_qr_pairing_v1.md` and `37_manual_pairing_cleanup.md`. Retained steps below are not current worker instructions.

# Controlled synthetic connection and pairing plan

Status: draft gate plan, 16 September 2026.

Current-state update (2026-09-17): historical evidence below predates successful synthetic pairing and later preparation. The installed 0.9.7+22 release SHA-256 is `34FBF72DAF3FA5D7E0355A05D8B2B49A39A4FB09448C1EB9A2B3B6929D209B20`; the older hash below is not its identity. Synthetic pairing/APK restart and offline preparation are user-passed. Internal upload/status integration is locally tested but not enabled in phone UI. The pairing-only listener is stopped. See `23_s3_pairing_test_preparation.md`, `28_configured_manual_sync.md` and the pending-review `29_controlled_upload_test_plan.md` for current scope/evidence.

This plan records the next safe path for connecting the ANSVK Outreach APK to the existing LAN Outreach foundation. It is a planning document only. It does not authorize starting a listener, changing office configuration, opening firewall access, pairing a phone, uploading records, acknowledging records, or deleting phone data.

## Current evidence

- APK release review build: `0.9.7+22`.
- APK release artifact: `build/app/outputs/flutter-apk/app-release.apk`.
- APK release SHA-256: `413E24677AAAEB4D4EFF50DF29A0755907F28E8DB2D74FEBA5F82451832DD484`.
- Phone test device: `ORCE49UWDQVGRC49`.
- User phone review result: passed.
- APK SQLite schema version: `6`.
- APK sync behavior today: certificate check and offline pairing request/response preparation exist; live pairing, upload, acknowledgement, retention cleanup and real sync remain inactive.
- LAN project location: `D:\LAN`.
- LAN Outreach foundation found: device API, pairing, sync, backups, browser admin routes, storage migrations and contract fixtures.
- LAN fixture checksum matched the APK fixture set: `719CED81397DF86B9C2F0F80538BBF3ECC43B7B987138CB3BF59B4E3B75683ED`.
- R1 APK PM readiness evidence: 17 accepted fixture files matched byte-for-byte between APK and LAN, LAN per-file checksums validated, selected Outreach/config/packaging tests passed, and LAN lint passed.
- R2 APK PM readiness evidence: focused Outreach LAN test suite passed, and full LAN regression passed.
- LAN Git status/HEAD could not be read because Windows Git reported dubious ownership for `D:/LAN`. This was recorded as a blocker for exact LAN commit identity until an administrator explicitly fixes or approves the Git safe-directory setting.
- LAN office/device API remains disabled for production use. No production `.env`, certificate, firewall, listener, real data or phone queue was changed during readiness checks.

## Source-of-truth documents

Dashboard and APK developers must read these before any implementation or live test:

- [01_plan.md](01_plan.md)
- [04_development_specification.md](04_development_specification.md)
- [06_local_database.md](06_local_database.md)
- [12_sync_architecture_decision.md](12_sync_architecture_decision.md)
- [13_dashboard_api_contract.md](13_dashboard_api_contract.md)
- [15_security_recovery_plan.md](15_security_recovery_plan.md)
- [17_pre_pilot_readiness.md](17_pre_pilot_readiness.md)
- [19_joint_sync_contract_status.md](19_joint_sync_contract_status.md)
- [22_s1_certificate_test_runbook.md](22_s1_certificate_test_runbook.md)
- `D:\LAN\docs\Outreach_LAN_API_Technical_Contract_v1.md`
- `D:\LAN\docs\Outreach_LAN_Security_Operations_Design.md`
- `D:\LAN\docs\fixtures\outreach\v1`

## S1: certificate-only connection test

Purpose: prove that the APK can reach a controlled HTTPS device API address and verify the server certificate fingerprint before any pairing or sync body is sent.

This stage is not live sync. It must not send a pairing request, upload a sync batch, acknowledge records, clear outbox rows, run retention cleanup, or use real client data.

Before S1 live action, record these items:

| Item | Required decision or evidence |
| --- | --- |
| Test style | Choose isolated synthetic listener or controlled office synthetic window. Prefer isolated synthetic state unless the project explicitly approves an office window. |
| Host identity | Windows host name, operator, installed LAN build identity if Git identity can be safely read, and whether the LAN office API is currently disabled. |
| Reachable address | Phone-reachable IP or host name, HTTPS port, and required base path. For the current contract this is `https://<office-server-ip>:3443/api/v1`. |
| Certificate source | Certificate owner, expiry date, SAN entries, and how staff will receive the approved SHA-256 fingerprint through a trusted channel. |
| Fingerprint rule | The full fingerprint is public verification data, but it must come from the trusted operator/dashboard display, not from an unverified endpoint as its own proof. |
| Firewall scope | Exact network scope and port exposure for the test, plus how it will be closed or reverted after the window. |
| Data isolation | Confirm no existing phone pending queue or real office Outreach data will be uploaded, modified, acknowledged or deleted. |
| Storage paths | Confirm LAN Outreach database and backup paths for the test state, or confirm that isolated temporary storage is used. |
| Roles | Name the data assistant/operator who controls the test window and the person holding the phone. |
| Rollback | Stop steps, config restore steps, firewall close steps, and evidence to capture after rollback. |

S1 success criteria:

- APK **Check certificate** succeeds when the saved dashboard address and approved fingerprint match the test server certificate.
- APK **Check certificate** fails for a wrong fingerprint or untrusted/nonmatching certificate.
- No pairing request is sent.
- No sync batch is sent.
- No phone operation is marked acknowledged.
- No retention cleanup runs.
- Existing LAN browser dashboard on port `3000` and existing MIS/LMIS behavior remain unchanged.

S1 must stop as blocked if we cannot assure synthetic isolation, cannot create a certificate with SAN for the phone-reachable address, cannot safely scope firewall/listener exposure, or cannot provide the fingerprint through a trusted channel.

## S2: live pairing implementation in the APK

Purpose: implement the actual APK action that sends the v1 pairing request and stores the returned device credential only after the HTTPS certificate is verified.

This stage needs separate approval before coding starts. The implementation must:

- Apply certificate pinning to the actual pairing request, not only to a separate earlier check.
- Send the exact v1 pairing request defined in [13_dashboard_api_contract.md](13_dashboard_api_contract.md).
- Reject malformed responses and responses with mismatched worker/device identity.
- Store the device credential only in Android secure storage.
- Never display, log, store in SQLite, or audit the device credential.
- Keep the pairing code if pairing fails before verified credential persistence.
- Remove or mark the pairing code consumed only after verified successful pairing state is stored.
- Avoid upload, acknowledgement, retention cleanup and real sync batch behavior.

S2 validation should happen first with automated synthetic server tests. A phone review APK should be built only after those tests pass.

## S3: one-device synthetic pairing window

Purpose: verify one phone can pair with the LAN Outreach foundation using synthetic data and an authorized one-time pairing code.

S3 must happen only after S1 passes and S2 is implemented and tested.

Preconditions:

- S1 certificate-only result is recorded.
- S2 APK pairing implementation tests pass.
- The review APK version, build number and SHA-256 are recorded.
- The LAN build identity is recorded, or the Git identity blocker is explicitly documented.
- A data assistant or authorized LAN role creates exactly one synthetic pairing code for the matching worker/device test.
- The test preserves the APK-generated `worker_id`.
- Existing real phone pending records are not uploaded.
- Sync batch upload remains disabled or out of scope.

S3 success criteria:

- Valid code over verified HTTPS pairs the phone and stores paired state on the phone.
- LAN records the paired device without exposing the device credential secret.
- Restarting the APK keeps paired state.
- Invalid, expired or already-used codes fail safely where those cases are available in the test window.
- One-active-device and revocation/retirement behavior is verified with synthetic state when approved.
- No sync batch upload, acknowledgement or cleanup occurs.

## Out of scope for this plan

- Production office sync enablement.
- Real client upload.
- Sync batch acknowledgement.
- Seven-day retention cleanup execution.
- Password recovery.
- Dashboard report UAT with real records.
- Browser HTTPS cutover.
- New dashboard repository creation.
- Changing `D:\LAN` Git safe-directory settings without explicit administrator approval.

## Next approval gate

The next practical approval should be narrow: approve S1 certificate-only test preparation and execution, using a controlled synthetic setup. That approval should name the Windows host, network address, test time window, operator, rollback owner and whether firewall/listener changes are allowed.

Do not approve a broad “enable sync” step yet. Pairing implementation, phone pairing, upload, acknowledgement and cleanup each need their own later gate.

