# Configured manual sync integration

Status: implemented and locally tested, 2026-09-17. Not connected to phone UI.

`ConfiguredManualSync` composes the existing repository, batch builder, secure fingerprint/credential stores, pinned HTTPS transport, status parser and manual runner. It requires a Paired connection and saved trust/credential. It captures the current worker, project/device identity and pairing settings for the run.

Before uploads, it performs authenticated GET `/api/v1/sync/status` and validates the expected device and worker, active state and agreed metadata. Empty queues perform this check too and return an empty-queue result without an empty upload. Status watermarks never acknowledge local operations.

Context guards recheck worker identity, app identity, complete pairing configuration, certificate fingerprint and credential before/after status, before each batch, after a batch response and after TLS/pin verification immediately before sending HTTP secrets. A changed/cleared configuration or lock stops the run. Concurrent runs on the same service instance are rejected. The runner retains previously applied confirmed marks if a later batch fails; exact SQLite receipt application remains transactional.

Verification: all 19 focused configured-service, runner, transport and real-loopback HTTPS tests passed; focused analysis is clean. Six new configured-service tests cover status before upload, authenticated empty-queue checks, foreign status, unpaired/missing credential, trust cleared during connection setup, pairing cleared during upload and worker lock during upload. Service tests inject HTTPS connections and use real in-memory SQLite; separate existing TLS tests exercise the concrete socket adapter.

No automatic retries, whole-sync success timestamp, retention cleanup, release build, phone installation or phone data changes occurred. Worker UI still disables live sending. The earlier pairing-only dashboard harness still blocks upload/status routes and must not be used for an upload test unchanged.

Next: prepare the controlled upload-test plan with LAN PM, including a synthetic dashboard store, permitted routes, expected records/acknowledgements and verification/rollback. UI integration and phone testing follow the agreed plan. Retry and completion behavior remain separate implementation work.

References: `13_dashboard_api_contract.md`, `20_phase2_apk_sync_implementation_plan.md`, `25_offline_acknowledgement_validation.md`, `26_manual_sync_orchestration.md`, `27_secure_sync_transport.md` and accepted v1 fixtures.

## Controlled first-test batch bound

Added `maxBatchesPerRun` to the runner and configured service on 2026-09-17. The first phone test will use 1. After full acceptance of the first batch, later batches remain pending and the result explicitly reports `batchLimitReached`, not full upload completion. Partial replies and failures still stop immediately. The default remains unrestricted for the existing internal flow; no UI is enabled. A batch retains the agreed 100-operation/1-MiB limits, so this does not guarantee a small or synthetic dataset; exact dry-run manifest review remains required. No automatic retry occurs.

Thirteen focused runner/configured-service tests passed with clean focused analysis, including limit validation, one-batch stop/resume and forwarding through the configured service.
