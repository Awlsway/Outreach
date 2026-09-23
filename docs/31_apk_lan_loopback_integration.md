# APK code against actual LAN upload harness

Status: end-to-end synthetic happy-path integration passed, 2026-09-17. No phone upload/build/install or firewall changes.

`test/lan_sync_end_to_end_test.dart` starts the reviewed LAN upload harness in a dedicated Node process through `tools/synthetic_upload/dart_bridge.mts`, on ephemeral 127.0.0.1 ports. It generates a disposable SAN-valid certificate, creates an entirely synthetic administrator through normal browser authentication, privately issues a code, and uses the production Dart pairing service and pinned socket transport to enroll a synthetic worker/device from real in-memory APK SQLite.

It then runs ConfiguredManualSync with the one-batch bound: worker/hotspot/encounter create operations (3 marks), exact-operation duplicate replay (0 additional marks), encounter update/delete revisions (2 marks), and authenticated empty-queue status. Dashboard inspections compare all five exact operation tuples, canonical operation hashes and canonical payload content against local immutable audits, and verify the actual daily backup. No whole-sync success timestamp or cleanup is written.

One end-to-end test passed. Focused Dart analysis is clean. The passing run stopped the exact servers/process, deleted its isolated dashboard state and temporary certificate/key, and closed the APK database. Earlier failed diagnostic runs were stopped; their protected synthetic state may remain and is not claimed deleted. No office/phone data was used.

## Interoperability mismatch discovered

The real APK generates UTC timestamps with up to six fractional digits. LAN sync-validation previously permitted only up to three, causing HTTP 400 invalid_payload despite successful pairing/status. Fixtures with whole seconds did not expose it. LAN PM updated validation to share `server/outreach/utc-timestamp.ts` and preserve UTC strings with up to six fractional digits. Outreach did not truncate or rewrite existing APK audits. The passing actual-harness test exercises real microsecond create/update/delete timestamps. LAN PM's standalone invalid-form/regression test completion report is pending because its task reached a usage limit; do not claim that suite passed from the file change alone.

## Test tooling findings

The subprocess output must be continuously drained, even when awaiting only private bridge protocol replies, to avoid blocked pipe writes masquerading as dashboard timeouts. Output is captured/discarded without exposing codes/credentials/payloads. One overlapping diagnostic attempt hit a Windows native SQLite DLL lock; test processes were allowed to exit and the final run was sequential.

Dashboard column `payload_hash` hashes the complete canonical operation, not just its payload. The test compares that definition correctly and separately compares canonical payload content. The UI's serialized payload SHA-256 is a distinct fingerprint and is not described as this backend column's value.

This test covers actual Dart/backend enrollment, happy-path uploads/revisions/duplicates/status and storage/backup compatibility. Fault cases remain covered by the separately recorded injected Dart tests and LAN-reported tests; no real-phone lost-response/retry/restart/release gate is claimed.

Next: obtain LAN's final timestamp-validation test report, review the exact phone outbound synthetic dataset and bind any future sending to the freshly reviewed frozen batch. Phone-facing tooling/window and sending remain disabled.

LAN final regression follow-up received: four test files/51 tests passed (timestamp validation, synthetic upload, sync and pairing); TypeScript lint and diff checks passed. Strict UTC Z timestamps accept zero or 1–6 fractional digits; greater precision, offsets, missing Z and malformed forms are rejected. Pairing and sync use the same validator and retain original strings. Outreach independently verified `utc-timestamp.ts` SHA-256 `3F3DB185D95911AFA3F6882E7AD3C94BBF0CA8268F2AC5BCFDD381E4FA37D708` and updated upload worker `54D6137321B643DDE27801357168DD788458D7C538D47317D6A77B3698EE676A`. The earlier pending report is now resolved. This is LAN-reported test execution, separate from Outreach's actual Dart end-to-end pass. Phone dataset review and exact frozen batch binding remain next; no live window is enabled.

References: `29_controlled_upload_test_plan.md`, `30_no_send_batch_review.md`, `27_secure_sync_transport.md`, LAN `docs/Outreach_U1_Synthetic_Upload_Test_Evidence.md`.
