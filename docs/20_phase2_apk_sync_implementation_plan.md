# Phase 2 APK sync implementation plan

**Status:** P2.1, P2.2, P2.3a and P2.3b offline preparation implemented; live P2.3-P2.8 are not authorized yet
**Date:** 2026-09-16  
**Owner:** Outreach APK team  
**Depends on:** LAN Phase 1 ingestion foundation and accepted v1 fixtures

## 1. Phase goal

Implement real manual APK synchronization against the LAN Dashboard HTTPS device API after the LAN Phase 1 ingestion foundation passes its final contract, regression and packaging gate.

Phase 2 turns the current APK sync preparation into real pairing, upload, acknowledgement tracking, retry handling, and safe retention cleanup. It must not change APK business rules or add cloud/background sync.

## 2. Start gate

Do not start real APK pairing, upload, acknowledgement or cleanup coding until LAN Phase 1 P1.8 passes and both teams confirm the same fixture checksums. P2.1 configuration alignment and P2.2 certificate checking were approved as preparation work before that gate.

P2.1 was separately authorized after the user's "ok proceed" instruction and LAN PM review. That authorization was limited to sync configuration UI alignment, local validation, secure-storage handling for the manually entered certificate fingerprint, and focused tests. It did not authorize network transport, certificate inspection, real pairing, upload, acknowledgement, retry handling, cleanup, deployment, or real data.

P2.2 was then separately authorized by the user's "can we proceed?" instruction. That authorization is limited to a local HTTPS certificate fingerprint check before future pairing/sync. It does not authorize a real pairing request, upload, acknowledgement, retry handling, cleanup, dashboard implementation, deployment, or real data.

P2.3a was authorized by the user's later "proceed" instruction as offline preparation only. It may build and test the future pairing request JSON shape and secure-storage holder for a future device credential. P2.3b then added offline parsing and validation for the accepted pairing success and error response shapes. These chunks must not send a pairing request, accept a pairing response as real, mark the phone paired, delete the saved pairing code, enable sync, build a release APK, install on a phone, or use real data.

Required LAN evidence before real APK pairing/upload implementation starts:

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

Status: implemented as a preparation-only change.

Purpose: update the current Dashboard Pairing preparation screen so workers and data assistant enter the future real connection details safely.

Tasks:

- Require HTTPS API address format such as `https://192.168.1.50:3443/api/v1`.
- Show that plain HTTP is not accepted for real phone sync.
- Add certificate SHA-256 fingerprint entry. Scanning is not required for this chunk.
- Keep the current state as preparation only until real pairing succeeds.
- Do not upload data from this screen.

Exit criteria:

- The APK refuses non-HTTPS phone sync URLs.
- Saved configuration survives app restart.
- Clearing configuration does not delete local outreach records or pending operations.

Implementation notes:

- The dashboard address must use `https` and end with `/api/v1`.
- The pairing code must be exactly six digits. Leading zeros are preserved.
- The full approved certificate SHA-256 fingerprint is normalized and stored in secure storage, not SQLite.
- Sync Status shows only a short fingerprint hint.
- The full APK SQLite schema remains version 6, matching the accepted v1 fixture contract.
- Phone test: a release-signed P2.1 test APK was installed on `ORCE49UWDQVGRC49`; the user reported that the preparation flow behaved as instructed and still did not sync.

### P2.2 Certificate fingerprint pinning

Status: implemented as a certificate-checking preparation change.

Purpose: prevent the APK from sending pairing or sync data to an untrusted dashboard.

Tasks:

- Fetch and inspect the server certificate before any pairing or sync body is sent.
- Compare the full SHA-256 fingerprint with the user-approved value.
- Keep the approved fingerprint in Android secure storage from P2.1.
- Show clear match, mismatch, invalid address, invalid fingerprint and unavailable messages.
- Leave planned two-fingerprint certificate rotation for the later real pairing/sync phase.

Exit criteria:

- The APK can perform a TLS certificate check without sending pairing or sync bodies.
- Matching and mismatching fingerprints are covered by local tests with fake certificate bytes.
- Invalid address, invalid fingerprint and unreachable-dashboard cases are covered by local tests.
- No certificate fingerprint or key material is written into SQLite audit payloads.
- Rotation fixtures remain deferred until real pairing/sync fixtures are implemented.

### P2.3 Pairing request and credential storage

Status: live pairing is not authorized; P2.3a offline request-building and credential-storage preparation is implemented; P2.3b offline response parsing is implemented.

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

P2.3a implementation notes:

- A local request builder can produce the accepted v1 pairing request JSON shape from app identity, signed-in worker profile, six-digit pairing code, app version and UTC request time.
- The signed-in worker helper reads only `worker_id`, `username` and `created_at`; it does not expose password verifier fields.
- A future device credential store exists in Android secure storage with an in-memory fallback for non-Android tests.
- P2.3b can parse accepted v1 pairing success and error response shapes offline, rejects success responses for another device or worker, and maps known error codes to worker-facing messages.
- The first S2 core pairing-engine chunk now adds the certificate-pinned pairing transport and paired-state application behind tests. No UI pairing button, sync enablement, phone install or live LAN connection has been added yet.

### P2.4 Build sync batch client

Status: not authorized.

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

Status: not authorized.

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

Status: not authorized.

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

Status: not authorized.

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

Status: not authorized.

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

The APK-side certificate checking code now exists, but real phone testing still needs the LAN dashboard to expose an HTTPS device API address and full certificate SHA-256 fingerprint. P2.3 UI wiring and live pairing review still depend on an approved LAN/S1 test window and a separate review build.

## 5. Runtime implementation boundary

This document authorizes only P2.1 and P2.2 preparation work. Until later Phase 2 chunks are separately authorized:

- the APK may perform the P2.2 TLS certificate check only; it must not send pairing or sync request bodies;
- the APK must not simulate successful sync;
- the APK must not mark operations acknowledged;
- the APK must not enable automatic retention cleanup;
- the accepted fixtures remain documentation and test-planning assets.
