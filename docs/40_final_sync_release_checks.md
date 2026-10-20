# Final APK and deployment checks — chunk 4

27 September 2026. APK development acceptance checks passed, including signed Sync/update and manual privacy checks. Office deployment gates remain pending; this is not real-data deployment approval.

## APK evidence

- Chunks 1–3 passed: exact client create/update/delete storage, ordinary Sync, destination-bound retention and legacy duplicate reconfirmation.
- Final focused checks: 38 passed for authentication, four-minute lock/activity/background behavior, ordinary Sync revoked/retired rejection, lost receipt, Stop and partial/multiple batches.
- Complete Flutter regression run: 144 passed, one outdated TLS exception expectation failed. Certificate mismatch now raises the intentional user-facing SyncRequestFailure instead of StateError. Only the test expectation was changed; affected TLS suite rerun passed all three tests. Final analysis has no errors and one pre-existing informational style hint.
- APK normal/debug and native synthetic flags are disabled. Signed candidate 0.9.10+25 built in 252.6 seconds (79.6 MB), APK SHA-256 `7B9F03463D9070A9350BAC619BB416E9FA4FC8DB3C3B437D752671129CF831EC`. APK Signature Scheme v2 verifies, signer certificate SHA-256 `d1950cfb4e667e15d3c5877d955cbae812b69dcaf3f8d7a23dda284279639dcb`. Package is `org.ansvk.ansvk_outreach`, DEBUG=false and native SYNTHETIC_SYNC_TEST=false; Dart synthetic flag was explicitly false. Fresh signed installation succeeded; initial signed enrollment/Sync passed: batch 268bcf74-d3bd-4e32-b2d5-921d5c1ef6b2 accepted three changes at 2026-09-27T08:03:28.621Z with zero rejected, correct worker/hotspot ownership, all canonical client fields matching and code0931 exactly once. Phone showed zero pending and matching receipt time. This revealed hard-coded pairing/batch app_version 0.9.9+24 despite installed 0.9.10+25; the artifact below supersedes this initial candidate. The signed package was absent before installation, so this is not evidence of upgrade from an older release.
- Current v1 contract fixtures are byte-identical to LAN. QR payload and encoded QR bytes also match. Checksum lists intentionally have different path scope: LAN additionally hashes its archived QR contract document; Outreach lists the two QR fixture files using relative paths. No fixture checksum was changed. All Outreach listed hashes verify; wire examples match despite the different checksum-list scope.
- Phone Wi-Fi off/on failure/recovery passed: user reported exhausted three retries, zero confirmed and changes retained. After Wi-Fi returned, batch `dbca8a11-9507-4cac-b0e3-e8a38f94e5c9` accepted two create operations, zero rejected, completed `2026-09-27T07:51:01.902Z`. Phone inspection verified zero pending and matching receipt time. Code `2026/MY/0930` exists exactly once at revision 1; dashboard operation identities/hashes are recorded privately in `chunk4-recovery-dashboard.json`. The failed-send UI was reported by the user; a later UI dump failed idle detection and was not used as failure evidence. Phone failure/recovery uses Wi-Fi off/on. Expired temporary firewall rule alone did not block access: general Node.js Any-port/Any-remote inbound rules exist for Public/Private profiles. No unrelated rules were modified. This is a deployment network-hardening item.

## LAN evidence and limits

LAN PM confirmed the automated staged-package gate, synthetic process restart/state reuse, assistant restrictions, current pinned certificate/address pairing, daily verified backups, and automated separate-directory restore/rejection tests.

Remaining office deployment gates:

- Administrator-run USB installer on a clean Windows host is not formally recorded.
- Current development server reports machine-binding failure and runs in grace mode. Strict authorized target-machine startup remains pending; no license override is approved here.
- Installed Windows service/boot restart is not proved by a development process restart.
- Office address, production certificate duration, renewal/rotation and address-change procedure remain deployment decisions. Current synthetic certificate expires 4 October; addresses stay in configuration/QR.
- Daily snapshots do not cover every later same-day upload. The owner-approved normal Admin API manual backup and separate-directory restore drill passed: backup outreach-20260927T075651Z.sqlite, SHA-256 `0af678624baae911386da8776ca5b7e018b574da35ba2d8d6f4df390b9952bed`, schema 4, integrity ok; 3 workers, 3 devices, 11 operations, 2 hotspots and 5 encounters. Exact operation IDs/hashes/history, entity revisions/deletion states, devices and batches matched the restored copy, including exactly one code0929 and one code0930. Runtime evidence: restore-drill-evidence-20260927T142620.json. Original users were restored byte-for-byte, temporary Admin access/helpers removed, live DB not replaced. Runtime restarted preserving state as PID23436. Further accepted data still requires an appropriate backup schedule; this snapshot is not continuous backup.
- Pilot-phone passcodes, worker training and every phone model must be checked before real data.

## Completion

Record final phone failure/recovery, release hash/signature/install, backup drill and remaining acceptance decisions before marking this chunk complete. Commit/merge only after the agreed four-chunk acceptance; preserve the existing QR branch. Passing development sync does not waive office deployment gates.

## Installed-version correction

Pairing, normal Sync and local/reviewed preparation now read BuildConfig.VERSION_NAME and VERSION_CODE through a dedicated Android metadata channel. Malformed native values fail rather than report a stale release version; absent native plugin falls back only in debug/test mode. pubspec version is now 0.9.10+25. No new dependency or enrollment reset is needed.

Native version tests passed two checks; ordinary Sync widget check passed; workspace suite passed all eleven after its I/O drain helper was updated for native completion before database work. No product code changed to satisfy the test timing. An unused test import was removed; the existing style hint remains.

Corrected candidate built in 106.7 seconds, SHA-256 `4C9EE623EE521D9330EB74B3F8163C452DF9A4F4EAC4833BC4C9927741A52172`. APK v2 signature verifies with the existing release key. Replacement install and launch succeeded over the signed package without clearing data. Replacement-install persistence and next Sync passed: batch `f2ec7984-f642-475d-a2c3-a674ba1e392d` reports app_version `0.9.10+25`, accepted one create, rejected zero, completed `2026-09-27T08:12:29.256Z`. Original worker/device/pairing remained unchanged; code0931 retains its encounter UUID/revision, and code0932 exists once with every field matching the canonical payload. Phone inspection confirms zero pending and exact receipt time. Ignored evidence: release-upgrade-verified.json and release-upgrade-phone.xml. Manual four-minute/background privacy acceptance remains pending; automated boundary tests passed. This is the current candidate; the earlier hash is superseded.

## Repository checkpoint

The owner accepted the APK checks and authorized housekeeping, commit and push on codex/synthetic-sync-uat-v1. Office deployment gates remain pending; main merge is not part of this checkpoint. Private signing/TLS files, generated APKs, caches and isolated runtime/backup evidence remain excluded from Git.
