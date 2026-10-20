# Seven-day phone client cleanup

27 September 2026: chunk 3 implementation and focused tests passed; ordinary debug build and phone upgrade/reconfirmation acceptance passed. Zero pending, the exact receipt time and removed 0/held 0 were verified; dashboard operation payload hashes and encounter revisions are unchanged. Production/pilot gates remain chunk 4.

## Rule and trigger

Keep today and the six preceding local calendar dates, computed directly as calendar dates. Encounters strictly before the cutoff may be removed after successful ordinary foreground Sync, including authenticated empty-queue checks. Partial, failed, revoked/retired or stopped sends do not trigger cleanup. Hotspots, peers, workers, credentials and project/device identity remain.

## Exact proof

Local migration 7 adds `sync_confirmations`: operation ID, worker/entity UUID, revision, sequence, project/device/dashboard IDs, batch ID and accepted time. It contains no client code, demographics, remark or payload and deliberately has no foreign key to removable audit rows. Non-identifying receipt references remain after cleanup.

The pinned configured service passes the expected dashboard ID to receipt application. Repository checks destination and batch/local identity, validates every sent operation against immutable audit, marks only exact accepted operations and saves encounter confirmation in the same transaction. A proof-insertion failure rolls back acknowledgement. Status watermarks never create confirmation.

Eligibility requires every revision from 1 through the latest local revision, same worker ownership, each relevant outbox acknowledgement, matching exact confirmation identity/revision/sequence/UTC time and current project/device/dashboard, and the latest accepted full payload matching every encounter field. Missing audit/outbox/proof, an unaccepted newer edit, foreign destination/owner or mismatched state keeps the record. The existing `old_client_records_held_unsynced` status count includes unproven/uncertain records; the screen calls this Held without complete sync proof.

## Transaction and copies

Remove encounter outbox rows first, then full client audit payloads, then encounter rows, in one SQLite transaction. No dashboard delete is queued. Recheck worker/Stop/context before deletion and before commit; transaction failure rolls back rows and retention timestamps. Update last checked time and eligible/held/removed counts; update last cleanup time only after actual removal. Cleanup failure keeps upload acknowledgements and reports that records were retained.

After removal, clear cached encounter/pending lists and selected client record in the workspace. Ordinary Sync clears frozen reviews before sending. Normal builds cannot export client batches; existing Android startup cleanup deletes legacy private review files even with the synthetic feature disabled. Reviewed one-batch test sends do not run retention. SQLite logical deletion does not claim forensic erasure of free pages; Android SQLCipher remains enabled.

## Upgrade and wire compatibility

APK local SQLite storage is version 7; independent `syncPayloadSchemaVersion` is 6 in pairing and sync envelopes. LAN PM approved this separation. API/protocol v1, synchronized entity shapes, fixture bytes/checksums and LAN internal storage are unchanged. LAN contract clarification is commit `dd2bece`.

Legacy encounter acknowledgements have no destination proof. Migration requeues previously acknowledged encounter operations by clearing only their outbox acknowledgement timestamp. Operation ID, entity/action/revision, occurrence time and exact payload remain unchanged. The next manual Sync reconfirms them using existing LAN duplicate handling without another entity revision. Historical successful-sync time is preserved until the next complete receipt. Other entity acknowledgements are untouched. Failed reconfirmation keeps records.

## Evidence and boundaries

Synthetic SQLite tests cover cutoff/year boundary; full payload removal; site/peer/proof preservation; unsynced/newer edits and deletion markers; missing evidence/wrong destination/state/foreign ownership; session/Stop/transaction rollback; and atomic proof insertion. Upgrade tests prove operation preservation and wire schema6 while local storage7. Service tests prove authenticated empty-queue cleanup and upload success surviving cleanup failure. Actual LAN loopback verifies duplicates, required backups, assistant role and rejection of wire schema7.

Do not change the phone clock to create old fixtures. Old-date deletion uses injected clocks and database fixtures. Phone acceptance checks upgrade/reconfirmation, zero pending, unchanged dashboard entity/revision history and retention screen counts/time. Detailed dated results are in `05_build_status.md`.

References: `38_sync_completion_plan.md`, `13_dashboard_api_contract.md`, `06_local_database.md`, `28_configured_manual_sync.md`, `14_worker_guide.md`; `lib/database/retention_cleanup.dart`, `outreach_repository.dart`, `schema.dart`; `lib/sync/sync_protocol.dart`, `configured_manual_sync.dart`; tests `retention_cleanup_test.dart`, `retention_migration_test.dart`, `configured_manual_sync_test.dart`, `lan_sync_end_to_end_test.dart`.
