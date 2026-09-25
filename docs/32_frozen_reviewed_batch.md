# Frozen reviewed batch safeguard

Implemented locally, 2026-09-17. Phone remains installed at 0.9.8+23; this code has not been built/installed yet. Live sending remains disabled.

ReviewedSyncPlan captures immutable prepared batch JSON strings, the exact complete pending-operation snapshot, worker/app identity and first-batch manifest in memory. The review screen now derives its manifest from this same frozen plan. Refresh/reprepare/disposal clear it; lock/session loss clears the plan and results. No plan is persisted or logged.

ConfiguredManualSync can receive the plan instead of rebuilding batches. Reviewed runs enforce one batch per run even if the configured general limit is different. Context guards validate the complete pending snapshot and identity before status, after status, before sending (including after TLS verification), and after a reply before applying marks. New operations, changed records/audits, previously acknowledged operations or identity changes invalidate review. The worker must prepare/review again. The exact frozen JSON reaches the transport unchanged; consumed review cannot be reused after acknowledgement.

The safeguard is wired internally and into local preparation; no upload action exists in the UI. UI review itself is not an authorization signal, and data classification remains manual. All immutable batch bodies remain sensitive service data held only within the signed-in session's memory.

Owner confirmed all pending records for the signed-in phone worker, including earlier hotspots/clients, are test data. This records owner confirmation, not an independent inspection of every phone payload. Actual outbound identity/count/hash review and approved phone-facing tooling/window remain required before a live upload.

Home network check: laptop Wi-Fi 192.168.1.7/24, phone wlan0 192.168.1.4/24, laptop gateway 192.168.1.1. These are point-in-time observations and must be rechecked before any window. No address, certificate, pairing or firewall settings were changed. Existing LAN successor remains loopback-only.

Verification includes exact frozen bytes, stale/new-operation rejection, changed context during connection, single-batch limits, lock-discard UI behavior, and actual Dart-to-LAN reviewed creates/update/delete/duplicate/status/storage/backup integration. Final focused test count is recorded in build status; focused analysis is clean.

Next: prepare a signed no-send review update when requested, and agree the phone-facing dashboard scope/window with LAN PM. Do not reinterpret the home-network IP check as permission to start an exposed listener or send records.

References: `29_controlled_upload_test_plan.md`, `30_no_send_batch_review.md`, `31_apk_lan_loopback_integration.md`.
