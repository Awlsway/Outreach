# Complete manual sync and phone retention

Planning review: 26 September 2026. Status: proposed execution plan; no implementation or tests performed during this review.

Execution update, 27 September 2026: chunk 1 passed. Create/update/delete sends passed exact dashboard payload/revision comparisons; the user confirmed zero pending and record absence after deletion. The initial client was Unspecified; New/Female details were verified on the subsequent update. See `05_build_status.md` for batches and evidence. The expired one-day certificate was deliberately replaced with a seven-day development certificate and the disposable synthetic APK data reset for fresh enrollment; dashboard identity/database/history were retained. Chunk 2 passed: ordinary debug Sync sent one client create, the dashboard stored it once with all payload fields matching, and the phone showed zero pending with the matching receipt time. Chunk 3 implementation, focused checks and upgrade/reconfirmation phone acceptance passed. The four replayed operations introduced no dashboard duplicate or revision changes; phone pending count is zero and receipt time matches. Chunk 4 APK development checks passed: failure/recovery, signed pairing/Sync/update, actual version metadata and manual privacy. LAN backup/restore passed. Owner accepted APK checks and authorized commit/push on the feature branch. Office deployment gates and main merge remain pending; see docs/40_final_sync_release_checks.md. See docs/39_seven_day_cleanup.md.

Preparation update, 26 September 2026: the previous `.5` and `.6` dashboard listeners are now stopped. The phone remains connected at `.2`, and the laptop Wi-Fi address is still `.5`. The `.5` runtime files and database remain present; its temporary certificate is valid until 26 September 2026 at 23:01:29 local time. Check time and address again before restarting. Outreach and LAN accepted fixture checksum files have the same SHA-256: `719ced81397df86b9c2f0f80538bbf3ecc43b7b987138cb3bf59b4e3b75683ed`. A file-by-file check found all contract fixtures and their checksum file identical across repositories. Only the two unchecksummed `README.md` files differ in historical runtime-status wording; this does not change the accepted wire examples.

## Outcome and scope

Finish four remaining chunks: client-record sync acceptance, normal worker Sync, safe seven-day phone cleanup, and pilot/release checks. Reuse QR enrollment, certificate pinning, device authentication, batch construction and exact acknowledgement handling already implemented. Do not rebuild pairing or add cloud sync, background sync, password recovery or dashboard reporting features.

The owner has confirmed the development data is synthetic and may be removed. Routine testing should nevertheless reuse the current working setup; resetting accounts and pairing is unnecessary unless the particular scenario requires it. This plan does not start a server, install an APK, send records, delete data or authorize production deployment.

## Current situation checked

| Area | Observed state |
| --- | --- |
| Outreach repository | `D:\outreach`, branch `codex/synthetic-sync-uat-v1`, HEAD `2107355`. Seventeen existing modified files include the four-minute lock, successful-sync timestamp fix, tests and documentation. Preserve and review them before committing. |
| LAN repository | `D:\LAN`, branch `codex/outreach-qr-pairing-v1`, HEAD `a8d50b3`. Git reported no modified files, with an inaccessible global ignore-file warning. |
| Installed APK | USB device `ORCE49UWDQVGRC49` is connected. Package `org.ansvk.ansvk_outreach.debug`, version `0.9.9`, build 24, updated 25 September at 23:54:04. Existing build notes identify this as the synthetic-send test build. |
| APK source | Inactivity timeout is four minutes. Normal builds still display sending-disabled text. Sending is available through the synthetic review path. Retention status explicitly reports cleanup disabled. |
| Current network | Laptop Wi-Fi `192.168.1.5`; phone Wi-Fi `192.168.1.2`. These are observations, not reserved addresses or production settings. |
| Current dashboard | No dashboard listener is running now. The existing `.5` runtime under `build/sync-uat-runtime-current-ip5` retains its database, certificate and recorded pairing/upload logs. When restarted with that configuration, browser address is `http://192.168.1.5:3000` and device API is `https://192.168.1.5:3443/api/v1`. |
| Older instance | The former `.6` listener is also stopped. Older runtime files exist, but are not the intended destination for the paired `.5` phone. No process termination was needed during preparation. |
| LAN build | `D:\LAN\dist\server.cjs` exists, last written 25 September at 10:32:36. Its authentication timeout agrees with source. A running listener alone does not prove phone reachability, firewall permission, certificate validity or that every compiled file matches current source. |
| Latest completed upload | Existing evidence records one worker and one hotspot accepted, two operations, zero rejected, zero pending on phone, and successful-sync time `2026-09-25T17:31:47.861Z`. The latest clean phone test contains no client records. |
| Prior coverage | Earlier actual-LAN loopback evidence already covers client create/update/delete and replay. QR lifecycle checks also have prior acceptance. Reuse that evidence; remaining phone acceptance is not a reason to repeat every earlier test. |
| Release gap | LAN P1.8 documentation still records administrator-run installation on a clean Windows host as pending. Current server logs also report machine-binding grace mode. Neither is production-installation proof. |

No HTTP requests, functional tests, builds or installations were run for this review. Phone checks were limited to connection, package metadata and Wi-Fi address. A subsequent read-only preparation check confirmed the retained LAN database contains one worker, one hotspot, zero encounters, two operations and one completed batch with two accepted and zero rejected operations. Its expected device `cbe76ba6-ca7e-4f6e-9471-98e13ae1fb3c` is active for worker `3a07935e-43b3-484a-9d53-38470a8ff4d5`. Live app screens and firewall rules were not independently revalidated here.

The retained certificate SAN is `192.168.1.5`; SHA-256 is `4920e6562176e9aa40d96cf7281f727930128368fd5df55d0d914ae42129e86a`. Its suffix agrees with the prior phone pairing evidence, but the exact current secure-store pin still requires confirmation at the test preflight. Database, certificate, key and backup paths in the `.5` runtime configuration all exist. No credential or private key was printed. Existing backup evidence proves prior successful writes, not a new current write-access check.

## Timeouts and restart decision

| Timer | Verified meaning | Action when execution starts |
| --- | --- | --- |
| Old restricted upload harness: maximum 30 minutes | `tools/synthetic_phone_upload/launcher.ts` closes its listeners at the approved deadline. | Do not assume this governs the ordinary dashboard currently running. |
| Temporary firewall guard | `tools/qr_pairing_uat/firewall_guard.ps1` removes its own rule at its supplied deadline or parent exit; it does not stop the dashboard. | Inspect actual rule state separately from server state. A ready marker is not proof the rule is still present. |
| Dashboard browser sign-in: 15 minutes | Source and built server expire the session from creation time. This is not a 30-minute server shutdown. | Sign in again locally when necessary. Browser expiry does not itself revoke the phone credential. |
| QR: five minutes | Enrollment payload has a short lifetime. | Generate only when the phone scanner is ready. Already paired phones need no new QR simply because it expired. |
| APK inactivity: four minutes | Current controller and prior focused tests use four minutes. | Keep this behavior; perform one manual boundary check in chunk 4. |

The dashboard listeners are now stopped. At execution time, check network, configuration, certificate dates/address and scoped firewall access first, then restart the intended development dashboard using its existing database, dashboard identity, certificate and credential configuration. The earlier QR UAT `start_window.ps1` creates a bounded 30-minute window from a separate UAT config; it is not a general restart command for the `.5` runtime. If the address or certificate no longer works, arrange a deliberate configuration/re-enrollment step; never disable certificate checks. Close only identified obsolete test processes and their own temporary rules.

## Execution preparation

1. Existing Outreach source/test diff reviewed; it contains the four-minute lock and successful-sync timestamp refresh, with no unrelated code changes found. `git diff --check` passed. Continue on the feature branch; do not move dirty work onto `main`. Review and commit with the final changes after acceptance.
2. Corrected outdated APK status text in `13_dashboard_api_contract.md`, `17_pre_pilot_readiness.md` and `36_qr_pairing_v1.md`. The LAN copy of the QR design and both fixture READMEs still contain historical wording; coordinate those documentation updates with LAN PM. Preserve historical evidence but identify it clearly.
3. LAN PM confirmed the retained `.5` runtime can be reused after configuration/trust/baseline checks; no LAN code change is currently needed for encounter create/update/soft-delete. They confirmed the foreground retry rules and that clean-Windows P1.8 installation remains pending. A separate restricted test dashboard is not automatically required for the owner's authorized synthetic testing. No LAN code or configuration change was made for preparation.
4. User enters dashboard and APK passwords directly in their login screens. Do not place passwords in chat, source, plan files, command arguments or logs. No credentials are needed for planning.
5. Use the installed debug APK for chunk 1 if suitable. Build/install only after a relevant code change; use debug development for iteration and one signed release candidate near completion.

Immediately before chunk 1: verify the laptop and phone are still on the same Wi-Fi, the `.5` certificate has not expired and matches the phone's saved trust, and the database/backup paths in the existing private runtime still exist. Start one dashboard process with that runtime's existing settings and a firewall rule scoped to the current phone address for the test window. Confirm both listeners and sign in locally. Keep credentials and private keys out of logs and documentation. If the certificate has expired, replace it and re-enroll the test phone deliberately; do not silently point the phone at a new certificate.

## Chunk 1 — Confirm client records reach the dashboard correctly

Owner: Outreach, with LAN support for read-only storage verification and any demonstrated backend defect.

1. Create one synthetic client visit dated the actual test day under the existing worker/hotspot. Use distinctive valid values covering client code, new/old fields, tests, distribution, recollection and referral.
2. Send and compare exact stored fields, owner, hotspot, encounter identity and revision with the phone's intended record. Check accepted operations, pending count and successful-sync time.
3. Edit that same day's record, send, and verify the new revision replaces the current values without creating a second encounter.
4. Delete the synthetic visit, send, and verify the dashboard deletion marker and audit history. Exclude it from active counts without losing server history.
5. Review existing replay/failed-ack evidence. Add or rerun targeted tests only where this workflow exposes an uncovered defect. Keep failure/recovery phone checks for chunk 4.

Exit: create, edit and delete agree on both sides; no duplicate encounter; pending counts and completion timestamps are correct. Record operation/revision evidence, not just a success banner. No new dashboard reporting screen is required to prove storage correctness.

LAN-confirmed mapping: client service records use `entity_type: encounter`, not a separate client entity. Create is revision 1 with full state. Update/delete provide exact `before` and `after` states with advancing revisions; delete has non-null `after.deleted_at`. The accepted worker and parent hotspot must exist, and actor/owner must match the paired worker. Outreach `client_code` must never link to MIS `CCode`. Report a payload mismatch before changing LAN to accommodate it.

## Chunk 2 — Enable normal worker-initiated Sync

Owner: Outreach. LAN work only for a verified contract/backend gap.

1. Wire the ordinary Sync screen to the existing configured sync service. Worker taps Sync once; normal use must not require USB export, laptop approval or the special reviewed-test button.
2. Preserve pinned HTTPS, active-device checks, owner/project guards, exact receipts, sequential dependency ordering, 100-operation/1-MiB batch bounds and the concurrent-send guard. Process all eligible batches; show partial progress honestly if a later batch fails.
3. Show usable states: ready, sending, completed, nothing pending, connection failure, rejected changes, revoked/retired and locked. Preserve unconfirmed changes and the previous successful-sync time on failure. Empty status checks must not invent a new upload completion time.
4. Follow the accepted LAN contract: after the first request, allow at most three foreground retries for transient network/storage failures, with jittered delays around 5, 15 and 30 seconds, visible progress and a Stop action. Stop or exhausted retries leave unacknowledged changes pending for the next manual Sync. Preserve operation identities and identical batch bytes on retry. Permanent validation failures are not retried automatically. There is no background retry.
5. Keep synthetic exports and test-only controls out of ordinary builds. Check both normal and synthetic feature configurations, not just the test build.

Exit: an ordinary debug build can send a synthetic record through worker Sync, complete multiple batches where necessary, and recover without duplicates or false acknowledgement. Tests target changed UI/service behavior and uncovered boundaries; do not rerun unrelated QR acceptance.

LAN-confirmed backup failure rule: if a required backup fails after storage commit, HTTP 503 withholds acknowledgement. The phone must retain unacknowledged operations and retry the identical batch safely; stored records must not duplicate. Empty queues use authenticated status, never an empty batch.

## Chunk 3 — Implement safe seven-day local cleanup

Owner: Outreach; LAN confirms its full-history behavior remains unchanged.

1. Use the existing calendar rule: keep today and six preceding local dates. Older encounters are candidates; this is not seven days since the upload.
2. Before deletion, positively prove the latest local revision and all relevant operations were acknowledged for the correct worker and destination. Absence of a pending row alone is insufficient proof. Hold unsynced, rejected, uncertain and newer-edited records.
3. Implement transactional removal of eligible local encounters and associated client-identifying audit/outbox payloads with correct foreign-key ordering. Preserve required non-identifying sync evidence, worker/device identity, hotspots and peers. Review all local copies before claiming client information is removed.
4. Distinguish retention from worker deletion: local cleanup must not enqueue a dashboard delete operation or erase dashboard history.
5. Run cleanup after successful foreground sync; include a successful authenticated empty-queue path so records that age after their last upload can be removed later. Recheck session/ownership and prevent concurrent edits from invalidating eligibility. Cleanup failure must not undo confirmed uploads.
6. Update retention checked/cleaned times and eligible/held/removed counts. Validate boundary dates, foreign ownership, missing acknowledgement evidence, newer revisions, deletion markers and transaction interruption with synthetic database fixtures. Do not change the phone clock to manufacture old records.

Exit: only proven eligible local client data disappears, unsynced data and hotspots remain, and dashboard current/history records remain intact. No claim of forensic storage erasure is implied by logical SQLite deletion.

## Chunk 4 — Finish focused pilot and release checks

Owner: Outreach for APK; LAN for installation, service, TLS, access and backup operations.

1. On phone, confirm four-minute inactivity lock, activity resetting the deadline, background concealment and re-login. Reuse prior automated boundary tests.
2. Exercise a connection interruption and recovery, lost acknowledgement/replay, and partial rejection at the appropriate layer. On phone demonstrate failure leaves data pending and Retry completes without duplication. Reuse existing automated fault-injection checks instead of recreating every fault manually.
3. Verify revoked/retired credentials cannot upload through the new ordinary Sync path; rely on existing QR lifecycle evidence for unchanged enrollment behavior.
4. LAN resolves stale server/rule cleanup, target-host machine binding, configured office address, certificate lifecycle, assistant access, service restart and backup/restore readiness. Daily verified backup evidence does not mean every later same-day upload already exists in that snapshot. Record the recovery exposure and restore result.
5. Verify or complete the documented clean-Windows installer gate. A reserved router address is not needed to finish current development tests; agree a maintainable office address before deployment. Addresses and certificates belong in deployment configuration/QR, not hard-coded APK values.
6. Review contract/fixture consistency and update worker instructions and status notes. Run required checks relevant to the final diff once, build the signed release candidate without synthetic controls, and perform a concise install/upgrade plus ordinary-sync check.
7. Review the final diff for secrets and generated runtime files, commit approved work on the feature branch, and merge only after acceptance. Preserve the old QR branch as requested. Record completion separately from permission to deploy with real data.

Exit: client sync, normal worker Sync and retention have evidence; release configuration and office operation have evidence; remaining risks are explicit. Mark any still-pending installer gate as pending rather than repeating all development tests.

## Order and evidence

Run preparation, then chunks 1, 2, 3 and 4. Reuse a single intended development dashboard while its configuration remains valid. At each chunk record the change, relevant checks, result and next step. If a check fails, fix that scope and rerun affected checks only. No extra approval round is needed merely to reuse already authorized synthetic data; actual privileged operations still follow tool permissions.

## References for both developers

- Outreach: `docs/01_plan.md`, `docs/05_build_status.md`, `docs/13_dashboard_api_contract.md`, `docs/17_pre_pilot_readiness.md`, `docs/20_phase2_apk_sync_implementation_plan.md`, `docs/28_configured_manual_sync.md`, `docs/31_apk_lan_loopback_integration.md`, and accepted fixtures under `docs`.
- Outreach implementation: `lib/auth/session_controller.dart`, `lib/database/schema.dart`, `lib/database/outreach_repository.dart`, `lib/hotspots/hotspot_workspace.dart`, `lib/sync/configured_manual_sync.dart`, `lib/sync/manual_sync_runner.dart`, `lib/sync/secure_sync_transport.dart`.
- LAN: `D:\LAN\docs\Outreach_LAN_API_Technical_Contract_v1.md`, `Outreach_P1.8_Contract_Packaging_Gate.md`, `Outreach_Backup_Restore_Runbook.md`, `QR_Pairing_Joint_UAT_Acceptance_2026-09-24.md`, and `docs/fixtures/outreach/v1`.
- Timeout evidence: LAN `server/middleware/auth.ts`, `server.ts`, `tools/synthetic_phone_upload/launcher.ts`, `tools/qr_pairing_uat/firewall_guard.ps1`; APK `session_controller.dart` and `qr_pairing_payload.dart`.

Historical readiness paragraphs in these references must be interpreted alongside current source and dated results. This review did not rerun their reported tests or certify production readiness.
