# Actual APK code against restricted one-batch dashboard

Status: two actual loopback end-to-end tests passed, 2026-09-17. No phone-facing listener, APK build/install, firewall change or phone upload.

Extended the existing synthetic Dart/LAN integration test to exercise both U1 and the separate restricted successor. The test bridge requires source127.0.0.1 and ephemeral listeners; it is not a live phone launch driver. The synthetic APK database/identity is created first and used for the exact enrollment-only approval. Normal browser administrator/code issuance and real pinned Dart pairing/status remain unchanged.

For the restricted case, the generated frozen batch is rejected before admission approval. The private automated test bridge installs the exact batch ID, raw UTF-8 SHA-256, canonical batch SHA-256 and ordered identity/revision/sequence tuples, explicitly confirming synthetic data and parent closure for this generated three-operation fixture only. No approval is issued for phone data by these tests.

Appending whitespace changes raw bytes while retaining equivalent JSON, and returns403. The configured reviewed run sends the unchanged frozen batch and marks exactly three worker/hotspot/encounter creates. Exact replay returns duplicate receipts with no additional marks. A later reviewed update/delete batch is rejected; both revisions remain pending, and backend accepted-operation count remains3. Exact stored operation tuples, canonical full-operation hashes and canonical payloads match local audits; actual daily backup verifies. The unrestricted U1 regression still accepts all five operations and authenticated empty-queue status.

Verification: `flutter test test/lan_sync_end_to_end_test.dart --no-pub --concurrency=1` passed both scenarios. Focused Dart analysis is clean. Each passing test stops its exact servers/process and deletes its disposable test root/certificate files. Test bridge continuously drains output without exposing secrets/payload logs. Installed phone remains0.9.8+23 and unchanged.

Next: implement/review a private phone manifest handoff and launch driver, prepare the appropriate signed test APK with frozen review/manual action under bounded scope, then recheck network/certificate and agree a live one-phone window. The phone-facing mode is not started by these local tests. No retries, retention, production readiness or backend restart recovery is claimed.

References: `29_controlled_upload_test_plan.md`, `32_frozen_reviewed_batch.md`, `33_one_phone_test_preparation.md`, LAN `docs/Outreach_One_Phone_Harness_Preparation.md`.
