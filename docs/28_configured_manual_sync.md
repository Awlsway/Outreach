# Configured manual sync integration

Status (27 September 2026): ordinary foreground worker Sync passed focused service/UI checks, normal debug installation and a synthetic client phone upload. Retention and production deployment remain separate gates. Historical test-stage notes below describe earlier configurations.

`ConfiguredManualSync` composes the existing repository, batch builder, secure fingerprint/credential stores, pinned HTTPS transport, status parser and manual runner. It requires a Paired connection and saved trust/credential. It captures the current worker, project/device identity and pairing settings for the run.

Before uploads, it performs authenticated GET `/api/v1/sync/status` and validates the expected device and worker, active state and agreed metadata. Empty queues perform this check too and return an empty-queue result without an empty upload. Status watermarks never acknowledge local operations.

Context guards recheck worker identity, app identity, complete pairing configuration, certificate fingerprint and credential before/after status, before each batch, after a batch response and after TLS/pin verification immediately before sending HTTP secrets. A changed/cleared configuration or lock stops the run. Concurrent runs on the same service instance are rejected. The runner retains previously applied confirmed marks if a later batch fails; exact SQLite receipt application remains transactional.

Verification: all 19 focused configured-service, runner, transport and real-loopback HTTPS tests passed; focused analysis is clean. Six new configured-service tests cover status before upload, authenticated empty-queue checks, foreign status, unpaired/missing credential, trust cleared during connection setup, pairing cleared during upload and worker lock during upload. Service tests inject HTTPS connections and use real in-memory SQLite; separate existing TLS tests exercise the concrete socket adapter.

The guarded synthetic test build completed a real phone upload to the development dashboard. Three synthetic operations were acknowledged after the dashboard created and verified its required backup. The first attempt correctly remained pending when the backup directory was missing; the retry reused the same operation IDs and did not duplicate records. Automatic retries and retention cleanup remain disabled. Do not use the synthetic UI path for production data.

References: `13_dashboard_api_contract.md`, `20_phase2_apk_sync_implementation_plan.md`, `25_offline_acknowledgement_validation.md`, `26_manual_sync_orchestration.md`, `27_secure_sync_transport.md` and accepted v1 fixtures.

## Controlled first-test batch bound

Added `maxBatchesPerRun` to the runner and configured service on 2026-09-17. The first phone test will use 1. After full acceptance of the first batch, later batches remain pending and the result explicitly reports `batchLimitReached`, not full upload completion. Partial replies and failures still stop immediately. The default remains unrestricted for the existing internal flow; no UI is enabled. A batch retains the agreed 100-operation/1-MiB limits, so this does not guarantee a small or synthetic dataset; exact dry-run manifest review remains required. No automatic retry occurs.

Thirteen focused runner/configured-service tests passed with clean focused analysis, including limit validation, one-batch stop/resume and forwarding through the configured service.

## Successful-sync timestamp and screen refresh (2026-09-25)

When a valid dashboard receipt accepts every operation in the current batch and the worker has no other pending operations, the APK saves `dashboard_received_at` to that worker's `sync_state.last_successful_sync_at` in the same SQLite transaction as the acknowledgements. Partial receipts, failed requests and batches that leave other operations pending do not update it. After a send, the Sync screen reloads the local status so the pending count and receipt time are current. Existing acknowledgements from before this change are not assigned an invented completion time; the field is populated after the next complete successful upload.

## Ordinary foreground Sync (27 September 2026)

The ordinary Sync button supplies a per-run cancellation/progress control to the existing configured service. It processes all prepared batches sequentially, authenticates status even for an empty queue and keeps exact receipt validation. The UI blocks concurrent sends/navigation while running, exposes Stop, refreshes counts/time afterward, and stops on session concealment, lock or disposal. Synthetic builds retain their reviewed one-batch path.

Transient SocketException/TimeoutException and HTTP 408/429/500/502/503/504 allow the initial request plus at most three foreground retries with 10% jitter around 5/15/30 seconds. Each retry reuses the same prepared batch and JSON bytes, rechecks the session/configuration and pins the new connection before secrets. Authentication, revoked/retired state, invalid replies, trust mismatch and changed context are not automatically retried. Stop interrupts waits and requests and closes the connection; late replies cannot mark local changes. Lost acknowledgements remain pending for duplicate-safe retry. Chunk 3 now runs proof-based retention after successful ordinary Sync; see `39_seven_day_cleanup.md`.
