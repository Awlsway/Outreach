# One-phone, one-batch test preparation

Status: LAN implementation evidence received and source/hash review completed, 2026-09-17. Actual APK-to-successor integration remains pending. No phone-facing service, firewall or phone upload is enabled.

Owner approved proceeding after the simple explanation of a temporary restricted dashboard. The current chunk implements/tests the separate successor locally. Automated synthetic administrator/code/device enrollment is included in these local tests. It does not start a live window or install a phone update.

Required restrictions: approved source phone IP, device/worker/project identity and exact device creation timestamp; one frozen approved batch ID and exact operation tuples; both raw UTF-8 body SHA-256 and separately labeled canonical JSON batch SHA-256; no additional or altered batch; identical replay only when explicitly requested; expiry shuts down listeners. Existing ordinary/S3/U1 servers remain unchanged. Normal device authentication, schema validation, actual durable storage and daily verified backups remain mandatory.

Tests must use isolated synthetic loopback/ephemeral ports and cover wrong source/identity/hash/ID/tuples, malformed or expired manifest, changed/additional batch, exact replay, expiry closure and backup failure after commit. Raw-byte verification must not log or persist raw bodies. Manifest schema/files/commands/hash evidence must be reviewed before APK interoperability with this successor.

APK prerequisites are locally implemented (28 focused tests pass): frozen review plan, stale-data/context guards and one-batch bound. Installed phone 0.9.8+23 has the earlier no-send screen; latest frozen-plan code is not installed. Owner confirms all pending worker records are test data, but exact outbound manifest review remains required. Point-in-time home addresses laptop192.168.1.7/phone192.168.1.4 must be rechecked before any live window.

Next after successor evidence: verify files/checksums and exact admission schema, then complete local APK interoperability and prepare a data-preserving phone update under the agreed scope. Phone-facing certificate/network/firewall/window remains a separate concrete step.

References: `29_controlled_upload_test_plan.md`, `31_apk_lan_loopback_integration.md`, `32_frozen_reviewed_batch.md`.

## Reviewed implementation evidence

LAN added separate `tools/synthetic_phone_upload` admission/device-app/launcher/guard/operator/worker files and two test files. LAN reports lint and four files/13 tests passed (six approval units, three successor scenarios, three U1 scenarios and S3 regression), including exact replay, backup failure after commit, verified backup/durable reopening and expiry closure. No live CLI/driver exists yet; startSyntheticPhone is an exported function requiring explicit configuration.

Outreach read the strict approval/admission/source guard, checked auth/validation-before-admission, hash-only express.verify with inflation disabled, actual daily-backup wiring and deadline scheduling. All six reported hashes match. Reviewed guard snapshot retained locally, SHA-256 `9107EAC416827AEAF51C084024B47FAC0F2D99C82A38641D867C355CC9CDDC25`. Thirteen independent local guard/regression tests passed (three new source/expiry tests, four U1, six S3). LAN integration execution is reported evidence, not an Outreach rerun.

Approval schema is version/sourceIp/expiresAt/identity(projectId,workerId,deviceId,deviceCreatedAt), with batch null during enrollment or frozen batchId/rawUtf8BodySha256/canonicalBatchSha256/syntheticDataConfirmed/parentClosureReviewed/ordered operation tuples. Admission is installed owner-locally after enrollment; identity/source/deadline remain fixed and an approved batch cannot be switched. Hashes use lowercase hex. Protected manifest and driver schema must be used exactly as documented in LAN `docs/Outreach_One_Phone_Harness_Preparation.md`.

Next bounded step: actual Dart frozen-batch integration against this successor on loopback, before proposing a private manifest-install/phone-facing driver or phone window. Phone data, app installation and network settings remain unchanged.

Follow-up: actual Dart integration against the successor and U1 regression both passed. Exact reviewed bytes accepted only after synthetic automated approval; modified bytes/later batch rejected, unaccepted operations pending, backend/backup evidence matched. See `34_restricted_dashboard_apk_integration.md`. The earlier pending APK integration gate is resolved; private phone handoff/driver/build/window remains next.
