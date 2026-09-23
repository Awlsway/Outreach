# Offline acknowledgement validation (P2.5a)

Status: implemented and locally tested, 2026-09-17. No upload or database acknowledgement application is enabled.

`lib/sync/sync_acknowledgement.dart` validates a dashboard receipt against the exact immutable prepared batch. It requires HTTP 200, `ok: true`, matching batch ID, and matching operation ID, entity type, entity ID, revision and sequence for every accepted or rejected entry. Unknown operations, duplicates, overlaps and malformed metadata reject the entire receipt.

Accepted entries retain their acceptance time and duplicate flag. Rejected entries retain their error and retryable flag. Missing operations are explicitly reported and prevent full acceptance. Warnings and retry delays never count as acceptance. Returned operation lists are immutable.

The parser has no database, credential or transport access. Rejected, missing or accepted operations all remain unchanged in the phone outbox at this stage. There is no retention cleanup or phone installation for this chunk.

Validation: all 24 focused acknowledgement/batch tests passed; focused Dart analysis found no issues. Coverage includes five accepted response fixtures, partial and duplicate receipts, mismatched identities, malformed metadata and missing operations.

The examples in `13_dashboard_api_contract.md` now match the accepted fixtures and LAN sync implementation: a processed partial batch uses HTTP 200 and `ok: true`, with separate accepted/rejected lists. An HTTP error or `ok: false` is not acknowledgement authority. Receipt metadata and operation sequence are shown explicitly.

## P2.5b local SQLite application

Implemented on 2026-09-17. `OutreachRepository.applySyncAcknowledgement` validates the receipt, current worker/project/device identity and every sent operation against immutable local audit data before writing. Only accepted operation IDs receive `acknowledged_at`, using the dashboard acceptance time. Replaying the same receipt preserves existing timestamps and makes no further marks.

All writes occur in one SQLite transaction. Rejected/missing operations and newer edits remain pending. Audit records and encounter records are preserved; no cleanup or whole-sync success timestamp is written. The future caller must supply a reply obtained through trusted certificate-pinned transport; this method is not connected to UI or transport yet.

All 38 focused acknowledgement, batching and database regression tests passed. Five new SQLite tests cover partial/missing receipts, newer edits, idempotent duplicate receipts, foreign identity/modified payload rejection, unavailable operations and rollback on a failure midway through the updates. No schema migration, APK version change, build, phone installation or phone data changes were needed.

Next chunk: design and test manual upload orchestration using controlled synthetic transport. Live transport and retention remain separate work.

References: `13_dashboard_api_contract.md`, `docs/fixtures/outreach/v1/`, `20_phase2_apk_sync_implementation_plan.md`, and `24_offline_sync_batch_preparation.md`.
