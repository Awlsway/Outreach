# No-send first-batch review

Implemented locally, 2026-09-17. No build/install or live sending.

In Sync status, Prepare changes locally now produces an expandable Review first batch — no sending section. It displays the first batch's project/worker/device/batch IDs, UTF-8 byte count and exact JSON-body SHA-256. Operation rows show username, hotspot name or client code; action, sequence and revision; expandable operation/entity IDs and SHA-256 of the serialized payload. Raw payload JSON, credentials, codes and medical fields are not displayed or logged.

The immutable metadata manifest does not retain batch payloads. Hashes describe the particular builder serialization used for that preview. Later preparation creates a different batch identity/time; a future live upload must use a freshly reviewed exact frozen batch, not assume an old preview authorizes a rebuilt one. That live binding is not implemented here.

Dependency checks examine the first batch in sequence order. Non-worker operations require an earlier worker create; encounters require an earlier matching hotspot create; revisions above 1 require the immediately preceding entity revision. If absent, the screen says dashboard confirmation is needed. This does not prove a parent is absent from the dashboard, and it never treats local acknowledgement watermarks as proof of a fresh dashboard's contents. Later batches are excluded from this preview and remain pending.

Every preview explicitly says test-data status is unverified. Record labels and hashes help identify operations but cannot classify all payload content as synthetic. Before a live window the data assistant must review the underlying records and the exact outbound manifest; unknown/real data blocks the test. No synthetic checkboxes, automatic approval or sending action were added.

Refresh/reopening clears the preview, preparation clears previous results, and worker/navigation guards discard late results. Existing worker-keyed workspace/session locking guards protect these details. Read-only preparation leaves SQLite audit/outbox records unchanged. Empty queues produce no review; failures expose only a safe generic message.

Verification: three pure manifest tests cover exact identities/hashes/immutability, missing parents and revision dependencies. Existing Sync widget regression now expands the first batch and operation, checks unverified wording and IDs/hash, verifies queue preservation, and verifies Refresh removes review. Focused Dart analysis is clean. Full focused manifest/workspace suite result is recorded in build status.

Next: review the no-send screen on a signed phone update when separately authorized, inspect the complete synthetic outbound dataset, and complete APK-to-actual-harness integration. Phone-facing dashboard tooling/window and live sending remain disabled.

Phone review update: owner authorized the signed review build. Version 0.9.8+23 built, verified and installed as a storage-preserving update; cold launch succeeded. All 25 focused manifest/workspace/pairing tests passed with clean focused analysis. Artifact identity is in `05_build_status.md`. User walkthrough remains pending: open Sync status, prepare locally, expand first batch and operation details, verify labels/no-send/unverified wording and unchanged pending count, then Refresh to clear review. No dashboard connection is needed. Live sending remains disabled.

Owner subsequently reported this requested phone walkthrough passed. U2 no-send screen review is user-accepted. This does not establish that the queue is synthetic, bind a future upload to this preview, or authorize live sending. Next is APK-to-actual-loopback-harness integration and exact outbound dataset review before a separately agreed phone window.

References: `29_controlled_upload_test_plan.md`, `28_configured_manual_sync.md`, `13_dashboard_api_contract.md`, accepted v1 fixtures.
