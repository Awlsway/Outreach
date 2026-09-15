# Phase 2 APK sync implementation plan

**Status:** Draft plan; runtime sync coding is not authorized yet  
**Date:** 2026-09-16  
**Owner:** Outreach APK team  
**Depends on:** LAN Phase 1 ingestion foundation and accepted v1 fixtures

## 1. Phase goal

Implement real manual APK synchronization against the LAN Dashboard HTTPS device API after the LAN Phase 1 ingestion foundation passes its final contract, regression and packaging gate.

Phase 2 turns the current APK sync preparation into real pairing, upload, acknowledgement tracking, retry handling, and safe retention cleanup. It must not change APK business rules or add cloud/background sync.

## 2. Start gate

Do not start APK runtime sync coding until LAN Phase 1 P1.8 passes and both teams confirm the same fixture checksums.

Required LAN evidence before APK implementation starts:

- HTTPS device API running on port `3443`.
- Accepted v1 fixture suite passing on LAN.
- Pairing, device credential, revocation and retirement behavior passing.
- Sync create/update/delete, duplicate, partial and error fixtures passing.
- `/api/v1/health` and `/api/v1/sync/status` implemented.
- Verified backup foundation implemented.
- Browser HTTPS cutover path documented for real-data readiness.
- No MIS/LMIS integration or regression from Outreach ingestion.

## 3. Work packages

### P2.1 Sync configuration UI alignment

Purpose: update the current Dashboard Pairing preparation screen so workers and data assistant enter the future real connection details safely.

Tasks:

- Require HTTPS API address format such as `https://192.168.1.20:3443/api/v1`.
- Show that plain HTTP is not accepted for real phone sync.
- Add certificate SHA-256 fingerprint entry or scan support.
- Keep the current state as preparation only until real pairing succeeds.
- Do not upload data from this screen.

Exit criteria:

- The APK refuses non-HTTPS phone sync URLs.
- Saved configuration survives app restart.
- Clearing configuration does not delete local outreach records or pending operations.

### P2.2 Certificate fingerprint pinning

Purpose: prevent the APK from sending pairing or sync data to an untrusted dashboard.

Tasks:

- Fetch and inspect the server certificate before any pairing or sync body is sent.
- Compare the full SHA-256 fingerprint with the user-approved value.
- Store the approved fingerprint in Android secure storage.
- Block unexpected certificate changes with a clear message.
- Support the planned rotation state where two fingerprints are temporarily approved.

Exit criteria:

- `untrusted_dashboard_certificate`, `dashboard_certificate_changed`, and `certificate_rotation_required` fixture cases pass.
- APK never sends pairing or sync body before certificate trust is established.
- No certificate fingerprint or key material is written into SQLite audit payloads.

### P2.3 Pairing request and credential storage

Purpose: pair the phone once and receive the hidden device credential.

Tasks:

- Send `POST /api/v1/pairing/requests` with `api_version=1`, `protocol=ansvk-outreach-sync`, `protocol_version=1`, `schema_version=6`, app identity, worker identity and six-digit pairing code.
- Store the returned device credential in Android secure storage.
- Store non-secret dashboard/device pairing state in the existing `dashboard_connection` table.
- Delete the saved pairing code after successful pairing.
- Show clear errors for invalid, expired, blocked, used, cancelled or already-active-device pairing cases.

Exit criteria:

- Pairing success and pairing-error fixtures pass.
- Device credential is never displayed, logged, stored in SQLite or included in audit payloads.
- The APK can restart and remain paired without asking for the pairing code again.

### P2.4 Build sync batch client

Purpose: send pending local audit operations exactly as the contract requires.

Tasks:

- Read pending rows from `sync_outbox` joined to `audit_operations` in ascending `sequence` order.
- Decode each local JSON payload and preserve current APK worker, hotspot and encounter payload shapes.
- Build batch headers with project, app, device, worker, protocol and schema values.
- Split pending operations into batches of at most 100 operations and 1 MiB JSON.
- Use the Bearer device credential automatically.
- Use `/api/v1/sync/status` when there are no pending operations.

Exit criteria:

- APK-generated request bodies match the accepted v1 fixtures for equivalent synthetic data.
- Empty pending queues use the status endpoint.
- Oversized queues remain pending and are split safely.

### P2.5 Apply acknowledgements safely

Purpose: mark only exact accepted operations as synced.

Tasks:

- Accept acknowledgement only for matching `operation_id`, `entity_type`, `entity_id` and `revision`.
- Set acknowledged metadata for accepted operations only.
- Leave rejected or missing operations pending.
- Preserve newer local revisions when an older revision is acknowledged.
- Show partial acceptance clearly.

Exit criteria:

- Create, revision, duplicate and partial response fixtures pass.
- No operation is removed from the pending queue unless exact acknowledgement is present.
- Failed or interrupted sync leaves all unacknowledged operations pending.

### P2.6 Retry, stop and availability behavior

Purpose: make manual sync reliable without hiding uncertainty.

Tasks:

- Use a 30-second upload timeout.
- After the initial request, allow at most three foreground retries after approximately 5, 15 and 30 seconds.
- Show progress and a Stop action.
- Keep all unacknowledged records pending after Stop, timeout or exhausted retries.
- Surface `rate_limited`, `service_unavailable`, revoked-device and retired-device states clearly.

Exit criteria:

- Retry and response-lost-after-commit fixture cases pass.
- Stop action prevents further requests and does not mark data synced.
- The UI never shows success unless all currently attempted operations are acknowledged.

### P2.7 Retention cleanup activation

Purpose: enable the seven-day phone cleanup only after exact dashboard acknowledgement works.

Tasks:

- Identify client/encounter records older than the phone retention window.
- Confirm their latest local operation revision is acknowledged.
- Remove only eligible local client/encounter operational copies.
- Keep hotspots on the phone.
- Keep unsynced, rejected, uncertain or newer-edited records.
- Include client-identifying audit payloads in cleanup only when safe under the same acknowledgement boundary.

Exit criteria:

- Cleanup never removes unsynced or uncertain data.
- Hotspots remain after cleanup.
- The dashboard remains the full-history store.
- Retention status shows what was eligible, held and cleaned.

### P2.8 Joint synthetic UAT and release gate

Purpose: prove APK Phase 2 against LAN Phase 1 before real data.

Tasks:

- Run APK unit tests for request construction, acknowledgement application, retry state and cleanup rules.
- Run APK against the accepted v1 fixture bundle.
- Run joint LAN/APK synthetic UAT over local Wi-Fi.
- Confirm no APK password verifier, SQLCipher key, certificate secret or device credential appears in payloads/logs.
- Build a signed release APK only after synthetic UAT passes.

Exit criteria:

- Accepted fixture coverage passes from APK side.
- One test phone pairs, syncs synthetic data, handles duplicate retry and partial rejection safely.
- Real-data release gates in [17_pre_pilot_readiness.md](17_pre_pilot_readiness.md) remain blocked until final PM acceptance.

## 4. Ordering review against LAN Phase 1

The LAN Phase 1 sequence is compatible with the APK architecture.

No contract mismatch was found. The ordering is correct because LAN first proves SQLite packaging, creates the isolated HTTPS server, adds durable storage, implements pairing/authentication, then sync processing, status, backups and final fixture verification. The APK should not implement real pairing/upload until that foundation is ready.

The only APK dependency to watch is certificate onboarding. APK Phase 2 needs the LAN dashboard to display the device API address and full certificate SHA-256 fingerprint before P2.2 and P2.3 can be tested on a phone.

## 5. Runtime implementation boundary

This document does not authorize runtime sync code. Until Phase 2 is separately authorized:

- the APK must not send real network sync requests;
- the APK must not simulate successful sync;
- the APK must not mark operations acknowledged;
- the APK must not enable automatic retention cleanup;
- the accepted fixtures remain documentation and test-planning assets.
