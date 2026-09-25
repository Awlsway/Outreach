# Controlled upload test plan

Status: LAN PM read-only review incorporated, 2026-09-17; implementation and live execution remain pending. Planning only; no service startup, firewall change, phone installation, pairing reset or upload is authorized by this document.

## Purpose and current state

Prove that the APK's secure manual Sync flow sends exact pending operations to an isolated dashboard, the dashboard stores them durably, and the APK marks only matching accepted operations. The internal flow passes 19 focused configured-service/runner/transport/real-loopback HTTPS tests. Phone build remains 0.9.7+22 with uploads disabled. Retention, automatic retries and whole-sync success timestamps are not implemented or enabled.

The old pairing-only test harness rejects sync status/uploads. It must remain unchanged for its existing purpose. The old service is stopped; its protected stores are retained. Backend restart/identity/credential persistence was not proved in that harness. A visible device ID or old Paired label does not establish that a new service accepts that credential.

## Required LAN review answers

1. Exact successor harness launcher, isolation boundaries and test-only route guard. It must use normal session/role/device authentication and the real sync/SQLite implementation; no bypasses or MIS/LMIS routes.
2. Fresh-store enrollment and identity/credential handling. Reuse of an old phone/store requires explicit supported restart evidence; otherwise use fresh synthetic enrollment after a separately agreed reset of pairing settings only, preserving local records and IDs.
3. Durable database evidence locations and queries for batches, operations, projected records, device status and duplicate receipts; no credential/verifier/key output.
4. Loopback integration evidence and fixture checksums before exposing a device listener.
5. Stop/rollback instructions and exact retained synthetic artifacts.

LAN PM review received through task PM on 2026-09-17. The requirements below incorporate that review. No implementation readiness or live availability is inferred from the browser tab.

## Reviewed dashboard requirements

- Create a separately named synthetic-upload launcher and guard. Leave the existing pairing-only launcher/guard intact; do not add a flag that silently changes the ordinary LAN server into a test server. Successor operator wording must truthfully state restricted synthetic upload mode rather than the old "Uploads blocked" message.
- Current S3 launcher always creates a new store and dashboard identity; it has no supported reopening path. Prefer a fresh empty upload-test store. Credential verification uses SHA-256; loss of the pairing pepper alone must not be described as invalidating existing device credentials. Reuse would require a separately reviewed reopening design, original identity, integrity/backup checks and certificate continuity.
- Isolate all SQLite/WAL/SHM, synthetic users, backups, reviews and repository paths in a protected test root. Set cwd/overrides before importing routes; never import ordinary startup/dotenv or copy production users/resources.
- Keep normal browser session/role and device credential authentication, worker/device creation-time binding, SQLite constraints, rate limits and request limits. Preserve strict path/method/no-query guards and browser Host/Origin/CSP/no-store protections. Review exact browser routes from the implementation; do not broadly expose backup or administration APIs.
- Wire the existing SyncService successful-sync callback to the actual `OutreachBackupService.ensureDailyBackup` behavior, as the normal device server does. The pairing-only harness omitted this because uploads were blocked. Test verified synthetic backups and failure behavior without fabricated acknowledgements.
- Record matching guard/fixture checksums, launcher identity, actual integration results and rollback evidence before a live window. Final successor paths and commands remain implementation deliverables, not guessed instructions.

## Authorization stages

## Reviewed phone-facing successor proposal (not implemented)

LAN PM proposes separate `tools/synthetic_phone_upload` tooling leaving S3/U1 unchanged. Approved window configuration must include freshly verified laptop/phone IPs, selected worker/device IDs and exact device creation timestamp, frozen batch ID/identity/operation tuples and hashes. Device HTTPS binds only the approved laptop Wi-Fi IP:3443 and permits only the approved phone source IP; operator binds only 127.0.0.1:3001. Check ports first. Fresh protected state/users/backups/reviews/repository and protected SAN-valid certificate, new dashboard identity, normal authentication and actual verified daily backups are mandatory. No backend restart/reopening claim.

After device authentication and batch validation, a separately reviewed admission check must reject additional/changed batches and accept only approved identity/ID/hash/tuples. Hash labels are critical: APK bodyHash is SHA-256 of exact UTF-8 JSON bytes; LAN canonical batch hash is SHA-256 of canonical JSON. Record both and compare each to its defined representation. Exact byte admission requires a reviewed raw-body verification hook; canonical-only admission establishes semantic equality, not byte equality. Never equate UI serialized payload hashes with the backend full canonical operation hash.

Store the window manifest outside Git with owner-only ACL; no credentials/codes/medical bodies/private keys in logs. The frozen batch must be prepared after fresh enrollment/settings stabilize, and remain unchanged; lock/refresh or queue changes require re-review. Expiry must close the test listeners; retain protected state/cert/evidence. If firewall access is needed, owner separately approves a unique rule limited to exact laptop IP, phone IP, Node executable and appropriate verified Private profile; do not broadly open Public/subnet access. Record internal/display names for rollback. Cancel unused codes, stop exact processes, verify listeners closed and remove only that window rule.

This proposal requires bounded successor implementation/loopback tests first, then phone build/install/certificate review and an explicitly agreed live window. None is enabled by the proposal itself. No phone-facing listener, firewall action, code issuance or upload occurred. Exact command/config schema and raw/canonical admission tests remain implementation deliverables.

## Authorization stages (continued)

U0 is this written plan/review only. U1 is the next proposed chunk: separately authorize implementation of the successor harness and automated loopback HTTPS/authentication/storage/backup tests with entirely synthetic enrollment/data. U1 does not enable phone uploads or expose a phone listener. Synthetic automated code issuance and enrollment must be included explicitly in that test scope and kept out of logs.

U2 follows U1 review: authorize phone Sync UI/build/install and a dry-run outbound manifest, with no sending. U3 follows both reviews: authorize one phone/live window, privately enroll against the fresh test store and send one small bounded batch once. The current runner can drain multiple batches, so the first-test one-batch bound must be enforced and tested before U3; a small UI selection alone cannot enforce it. These stages are not authorized automatically by receipt of this review.

## Stage U1: laptop-only actual dashboard API test

LAN prepares a fresh protected synthetic store and test certificate. Browser admin stays loopback-only. Proposed device allowlist: GET `/api/v1/health`, GET `/api/v1/sync/status`, POST `/api/v1/pairing/requests`, POST `/api/v1/sync/batches`; all unrelated routes and unsupported methods/query variants blocked before body parsing. Exact browser operator/auth/code paths must be reviewed from the actual launcher. Never share production users, environment, certificates or database files.

Using an entirely synthetic in-memory APK database and accepted fixtures, exercise pinned transport, normal enrollment, status, create/update/delete, duplicate replay and partial rejection. Record exact batch IDs, operation IDs, entity IDs/revisions/sequences and expected pending counts before each action. Device/status/receipt identities must match the test project and worker. Fixtures must match both repositories byte-for-byte.

Pass evidence: accepted operations and projected records are durably present in the isolated dashboard; exact accepted local outbox rows carry acknowledgement times; rejected/missing rows and newer revisions remain pending; audit history is unchanged; identical replay creates no duplicate operations or records. Status checks alone mark nothing. No retention runs, and no whole-sync completion timestamp is claimed.

Failure coverage: wrong certificate sends no HTTP secrets; invalid/revoked credentials stop before upload; wrong device status blocks uploads; malformed/mismatched receipts mark nothing; partial replies stop dependent later batches; lost replies leave unconfirmed operations pending and replay remains idempotent; locks/configuration changes stop the run. Fault injection must be restricted to test infrastructure, not production code. Automatic retry is not claimed.

Additional LAN review cases belong in automated isolated tests first: well-formed unauthenticated requests return 401 (malformed JSON can fail parsing first); mismatched worker/device/device creation time returns 403; changed content for a reused batch identity returns 409; parent/revision gaps preserve pending operations; timeout, cancellation and storage/backup failures produce no false phone marks; size limits produce 413. Revocation/retirement tests use separate synthetic devices, not the owner's phone. Failed/rejected requests may write security audit or batch state even with zero accepted operations; inspect those categories separately.

## Stage U2: phone UI review and controlled upload

Start only after U1 passes and both PMs document the exact test setup. Implement a review UI with explicit user-tapped Sync, safe pending/confirmed counts and partial/failure wording. Keep retention disabled and do not label a partial run or an empty-queue status check as a completed full sync. Build/sign/install as a data-preserving update under the agreed test window.

Before any phone upload, confirm the entire selected worker queue contains synthetic data: the current runner sends all pending operations for that worker. A single new synthetic record does not isolate older pending records. If the existing queue cannot be confirmed synthetic, use a dedicated clean test phone/profile whose ownership and enrollment are explicitly agreed; never purge the existing phone queue to make a test possible.

The dry-run manifest must enumerate the actual outbound batch/operation IDs, entity types/IDs, revisions, sequences, worker/device/project identity and payload hashes without sending. Confirm every payload is synthetic and parent closure is complete. Counts alone cannot establish this. Record exact expected accepted tuples and pending IDs; no credential, pairing code, cookie or private key belongs in evidence logs.

Record actual laptop/phone Wi-Fi addresses, certificate SAN/expiry/trusted fingerprint, exact API address, operator, selected worker/device/project IDs and expected queue contents. Determine a narrowly scoped temporary firewall rule only if needed; the owner runs administrator changes. Do not reuse historical IP addresses as current facts.

If fresh enrollment is required, owner explicitly clears saved pairing/hidden credential only and uses a fresh code in the agreed isolated store. Verify records/IDs/outbox preserved. The owner taps Sync; compare dashboard durable records and APK exact pending counts before/after, then check persistence after APK restart. Backend restart is a separate test unless supported by the reviewed harness.

## Rollback and closeout

Cancel unused codes before shutdown, gracefully stop the exact test processes, verify no test listeners remain, and remove only the test window's firewall rule. Record both internal rule name and display name correctly. Retain protected synthetic stores, verified backups and manifests until agreed cleanup. Never reverse valid local acknowledgement marks by hand: they refer to records stored in the isolated test dashboard and are test data only. Do not uninstall the APK, clear storage, delete audit/outbox records or run retention as rollback. Owner-approved local test pairing clear is optional and separate. Document remaining settings; an unavailable test dashboard must not be presented as operational readiness.

## References for both teams

- `13_dashboard_api_contract.md` and `19_joint_sync_contract_status.md`
- `20_phase2_apk_sync_implementation_plan.md`
- `23_s3_pairing_test_preparation.md`
- `24_offline_sync_batch_preparation.md` through `28_configured_manual_sync.md`
- Accepted v1 fixture directories in both repositories
- LAN `docs/Outreach_LAN_API_Technical_Contract_v1.md`
- LAN `docs/Outreach_S3_Isolated_Harness_Preparation.md`

U1 authorization update (2026-09-17): owner said proceed after the reviewed plan's proposed laptop implementation/test step. LAN PM has been instructed to implement the separate successor and actual loopback authentication/storage/backup tests with synthetic automated enrollment explicitly included. Work/evidence pending. No phone/network window authorized.

APK prerequisite completed: runner/configured-service one-batch per-run bound implemented and locally tested (13 focused tests passed; focused analysis clean). The first phone run must set the bound to 1. Manifest review and a deliberately small dataset remain required; the bound alone does not classify data or prevent a 100-operation first batch.

## U1 reviewed evidence

Frozen-review follow-up: 28 focused UI/service/runner/actual-LAN tests passed. The locally prepared first-batch manifest now comes from the exact retained immutable batch; reviewed sending rejects pending-data/identity changes and forces one batch. Refresh/lock discard review. Owner confirmed all pending worker records are test data. No live upload or phone update enabled. Home IPs observed laptop192.168.1.7/phone192.168.1.4; actual manifest and current window/network/certificate checks still required. See `32_frozen_reviewed_batch.md`. LAN PM asked for read-only phone-facing scope proposal; no listener changes dispatched.

Final timestamp follow-up: LAN reports 4 files/51 tests and lint passed; Outreach verified updated timestamp-validator/upload-worker hashes. The pending regression report mentioned below is resolved. Phone dataset verification, frozen batch binding and phone-facing window remain separate incomplete gates.

LAN PM reports completion of `tools/synthetic_upload/{launcher.ts,request_guard.mjs,operator_page.ts,integration_worker.ts}`, `server/__tests__/outreach-synthetic-upload.test.ts` and `docs/Outreach_U1_Synthetic_Upload_Test_Evidence.md`. TypeScript lint passed; two test files/three scenarios passed (upload success, backup failure/recovery, S3 regression). Coverage includes actual HTTPS/authentication/SQLite, exact receipts and payload hashes, duplicates/conflicts, revisions/delete/partial rejection, limits, revocation, durable storage reopening and verified backups. This is LAN-reported execution evidence, not an Outreach rerun of that suite.

Outreach independently read the launcher/guard/evidence and verified the supplied four tool hashes. The launcher rejects non-127.0.0.1 hosts, sets isolated cwd/overrides before dynamic ordinary route import, wraps both servers before listen, and connects the real daily-backup callback. Matching reviewed guard snapshot is retained at `tools/synthetic_upload/request_guard.mjs`; its SHA-256 is `F9B0731222734054ACF8540DF0C02B651954BD636D569CC9E3A2AAA43568711B`. All 16 manifest-listed contract fixtures matched both repositories. Ten Outreach guard tests passed (four upload-scope and six unchanged S3 tests); the old S3 guard retains `177CCAEAB9976473E27F46D6ECAE640F79BF35F8B5374951E6BA565AB936483E`.

Backup semantics: backup failure returns 503 without an acceptance receipt even when operations were committed. Restoring storage and replaying the same batch produces duplicate acceptance and a verified backup. The first daily snapshot contained three operations; later same-day operations do not force another daily snapshot. Do not imply that every accepted operation already appears in a fresh backup snapshot. Exact durable operation storage and verified daily backup evidence are separate checks.

LAN reports listeners closed, disposable roots deleted, and source environment/users/S3 hashes unchanged. No phone-facing mode exists in this successor. U1 backend preparation is reviewed; APK-to-actual-harness end-to-end tests, phone UI/dry-run data manifest, approved phone-facing tooling/window and current network/certificate/firewall details remain readiness gates. Production use, retries/completion behavior, retention, backend restart persistence and clean-host release verification remain separate.

Next proposed chunk: U2 phone review UI and dry-run outbound manifest, with the one-batch bound and no live sending. Any phone-facing successor change/window must be agreed with LAN PM before U3.

Progress follow-up: U2 no-send phone screen is user-passed on 0.9.8+23. APK-to-actual-LAN loopback happy-path integration now passes with synthetic data, including exact five-operation/payload checks and verified daily backup. It discovered and exercised a LAN microsecond timestamp compatibility fix; LAN standalone validator regression completion report is pending. See `30_no_send_batch_review.md` and `31_apk_lan_loopback_integration.md`. Actual phone synthetic dataset verification, frozen preview/send binding, phone-facing tooling/window and live upload remain incomplete; older proposed-stage text records historical scope.
