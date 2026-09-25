# Manual sync orchestration: fake transport chunk

Status: implemented and tested locally, 2026-09-17.

`ManualSyncRunner` prepares the signed-in worker's pending operations and sends immutable batches sequentially through an injected `SyncBatchTransport`. There is no concrete network implementation or UI wiring. Automated tests inject a fake dashboard connection and use real in-memory SQLite.

Each reply must pass exact receipt validation and transactional audit/outbox checks. Partial or missing acknowledgements stop later batches to avoid proceeding past unconfirmed dependencies. A connection or validation failure stops the run while retaining earlier confirmed marks and leaving all unconfirmed operations pending. Concurrent runs on the same runner are rejected. Session changes prevent receipt application.

An empty queue returns an explicit empty-queue result, not dashboard sync success. Authenticated `/sync/status` checking remains future work. No automatic retry, success timestamp, cleanup, credential handling or production transport is enabled. The result reports newly marked operation count and a safe outcome; raw payloads and transport errors are not displayed or logged.

Validation: nine focused orchestration/SQLite tests passed, including four new runner tests for ordered multi-batch success, partial stop, connection failure/resume, concurrent invocation and lock while awaiting a reply. Focused analysis is clean. No APK build, installation or phone data changes occurred.

Next chunk: specify the authenticated, certificate-pinned transport and status checks, then test its failure cases before a controlled live dashboard test. Retry policy and whole-sync completion remain separate work.

References: `13_dashboard_api_contract.md`, `20_phase2_apk_sync_implementation_plan.md`, `24_offline_sync_batch_preparation.md`, `25_offline_acknowledgement_validation.md`.
