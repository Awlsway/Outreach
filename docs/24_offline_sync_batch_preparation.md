# Offline sync batch preparation

Status: P2.4a builder and P2.4b local UI completed, 17 September 2026. Signed phone review update 0.9.7+22 installed and requested offline phone walkthrough user-passed. Network upload is not enabled.

## Sync Status action

Added **Prepare changes locally** to Sync Status. It prepares the current signed-in worker's pending operations and shows prepared changes, batches and total encoded bytes, with an explicit no-data-sent result. It does not require a live dashboard or read a dashboard credential. Prepared request bodies are not retained in widget state or displayed.

Empty queues show a no-pending-changes result. Failure shows a generic review message without parsing exception text or client payload details. Records/outbox remain untouched. Refresh/reopening Sync Status clears the prior result. Results are discarded after navigation or a changed signed-in worker. Connection wording now reflects actual paired state while making clear that sending is disabled.

All 18 focused widget/builder tests passed, including real pending-queue preparation/preservation, refresh invalidation, empty queue and malformed payload privacy. Focused Dart analysis returned no issues. No new APK build/install was performed in this UI chunk.

## Implemented

`lib/sync/sync_batch_builder.dart` converts a signed-in worker's pending audit/outbox rows into the accepted v1 request format. Callers supply app identity, worker ID and pending operations from the existing worker-scoped repository. This pure builder does not read credentials, contact a dashboard, write SQLite, acknowledge operations or run cleanup.

Headers use agreed protocol/API values, current SQLite schema version, supplied application version, project/device/worker identity, batch UUID and UTC creation time. Payload strings become JSON objects. Only agreed operation fields are included. Ownership, operation IDs/sequences, supported actions, snapshot identity/revision and unexpected payload fields are checked.

Operations are sorted by local sequence and split at 100 operations or 1 MiB of complete UTF-8 JSON, including headers. Returned batches store immutable encoded JSON for eventual retry. If one operation cannot fit, preparation fails without skipping dependencies. All records remain pending because there are no writes. Empty queues return no batches; future transport must use `/sync/status`, which this chunk does not call.

## Validation

Eight focused tests passed: exact equality with accepted create/revisions/partial/no-GPS fixtures; 201-operation splitting and stable encoded bodies; UTF-8 byte limits including Burmese text; oversize rejection; foreign ownership/duplicate IDs/malformed JSON/unexpected secret-field rejection; actual SQLite create/update/delete queue preservation. Focused Dart analysis returned no issues. Fixture versions remain historical; tests supply their recorded app version.

## Next chunk

Build/install a signed phone review update and verify the preparation action/counts while offline. Keep upload disabled until authenticated pinned transport and exact acknowledgement handling receive their own gates. Data sending, sync activation and production-readiness claims are outside this chunk.

## References

- [Dashboard API contract](13_dashboard_api_contract.md)
- [Joint contract decisions](19_joint_sync_contract_status.md)
- [Phase 2 implementation plan](20_phase2_apk_sync_implementation_plan.md)
- [Accepted fixtures](fixtures/outreach/v1/README.md)
