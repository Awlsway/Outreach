# Outreach APK verification and release status

Updated: 2026-10-20. Owner: Outreach APK PM. This document distinguishes current
UI acceptance/artifacts from the historical renewal checkpoint and remaining
office deployment gates.

## Current UI candidate — 20 October

The Today-first UI refresh is on `codex/ui-ux-refresh`, based on pushed
`6d36c31`. The owner authorized a checkpoint commit/push on 2026-10-20,
without merging to main. Use `git log -1` and branch tracking for the resulting
checkpoint. [UI refresh evidence](49_ui_ux_refresh.md)
records all seven chunks: focused checks at each stage, direct local phone
checks and the owner's **Passed — I accept the UI** reply. The last form chunk
passed 34 distinct checks across five suites; two version-reader checks passed
with 0.9.12+27 included. No fresh full-suite run is claimed.

- Signed candidate: `build/ui-refresh-uat/20261020/ANSVK-Outreach-0.9.12-27-ui-refresh.apk`.
- Package/version: `org.ansvk.ansvk_outreach`, **0.9.12+27**, 84,341,490 bytes.
- SHA-256: `9BA9D543C6366987E39D054904293E98DFF02AB7761E7D3E176D8279BF6A2018`.
- APK Signature Scheme v2 verified; release signer matches the previous release.
  Non-debuggable, Android backup disabled, synthetic review flags false, native
  screen-capture protection retained.
- Installed over signed build 26 with `adb install -r`, retaining first-install
  date `2026-10-01 00:27:20`; version 0.9.12/build 27 and existing-account Sign in
  launch confirmed. No app-data clear/uninstall occurred.
- Full local UI journey and owner acceptance were on the separate debug Test
  app; signed verification covers package/update/launch. No new dashboard
  pairing/upload or signed Sync UAT occurred. Database/auth/sync/Android source
  and dependencies are unchanged; only UI and package version metadata changed.
- This candidate comes from the current working tree, with source hashes recorded
  in the UI evidence folder. A commit-based byte-for-byte rebuild is not claimed.
  The older named signed 0.9.11+26 APK remains preserved with its original hash;
  generic `app-release.apk` now contains 0.9.12+27.

The sections below retain the **1 October renewal baseline**. Their older
artifact/commit statements do not describe the new UI candidate above.

## Git and signed artifact — 1 October baseline

- Remote: `https://github.com/Awlsway/Outreach.git`; checkpoint branch `codex/synthetic-sync-uat-v1`, based on `fed2b46cf8e42b8dd5c251033d29252a60d259ff` (`Enable ordinary sync and verified seven-day phone retention`). Check `git log -1` for the renewal source-checkpoint commit. No merge to `main` or push is claimed here.
- At the start of this checkpoint, the approved certificate validation, initial trust and renewal source/tests/docs were modified/untracked beyond that base commit. They were reviewed for this checkpoint. Unrelated untracked `android/Kimi-Test.code-workspace` is intentionally excluded. Check `git status` for any later work; the base commit alone does **not** represent the signed candidate.
- Signed candidate `D:/outreach/build/renewal-test/ANSVK-Outreach-0.9.11-26-renewal-test.apk`: package `org.ansvk.ansvk_outreach`, version **0.9.11+26**, 84,128,378 bytes, SHA-256 `FE1007F8C67FBF52EF78DBCD7C1CE347261F763B56F961626ECC5EE0F265BCA4`. Read-only `Get-FileHash` on 2026-10-01 matched this value for both the named candidate and generic `build/app/outputs/flutter-apk/app-release.apk`.
- [Package evidence](48_certificate_renewal_signed_candidate.md) records APK Signature Scheme v2, signer continuity, non-debuggable manifest, disabled Android backup and disabled synthetic controls. Release signer SHA-256 is recorded there. This candidate was built from the dirty workspace, not reproducibly from HEAD alone.
- The prior signed 0.9.10+25 artifact is separately preserved at `build/apk-checkpoints/0.9.10-25/`; its previous phone/Sync acceptance is historical, not evidence for renewal in 0.9.11+26.
- Checkpoint verification on 2026-10-01: the affected renewal/pairing/ordinary-Sync run passed **241/241 tests** across 12 suites; `dart analyze` of eight renewal/trust source files found no issues; all six renewal fixture files matched LAN byte-for-byte; `git diff --check` found no whitespace errors. `flutter analyze --no-pub` produced no result within roughly a minute and was stopped, so it is not counted as a pass. No APK rebuild/install was done for this checkpoint.

## Passed evidence and limits

| Area | Recorded evidence | Boundary |
| --- | --- | --- |
| Offline worker data, ordinary Sync and seven-day retention | [Final sync checks](40_final_sync_release_checks.md) and preceding field/retention documents record own-record flows, create/update/delete, exact acknowledgements, retries, failed-Sync preservation, signed release Sync and retention safeguards | Synthetic data and a development LAN setup; no real-data rollout approval |
| Certificate validity, initial trust and renewal source | [Validation](41_certificate_validation.md), [initial trust](43_initial_certificate_trust.md), [QR/review](44_certificate_renewal_qr_review.md), [durable transition](45_certificate_renewal_transition.md), [normal Sync UI](46_certificate_renewal_sync_navigation.md) record scoped passing tests and analysis; latest affected UI run had 241 passing tests across 12 suites | Focused runs at different checkpoints, not a fresh full-suite run for this handoff; desktop TLS/FFI is not physical Android by itself |
| Android build/signing | [Debug package check](47_certificate_renewal_android_build.md) and [signed candidate check](48_certificate_renewal_signed_candidate.md) passed; the candidate checksum was rechecked above | Package inspection alone cannot prove installed runtime or preserve-data update |
| Joint signed-phone UAT | LAN [1 October phone UAT](../../LAN/docs/Outreach_Phone_Renewal_UAT_2026_10_01.md) records installed 0.9.11+26, QR pairing, generation 1-to-2 renewal preserving two pending hotspot/client changes, successful post-renewal Sync, force-stop/reopen, same-backend restart and a one-change outage/retry accepted exactly once with pending zero | Isolated synthetic backend; not office production installation. Lost-ack replay and interruption during renewal claim/confirmation were not physically proven; enlarged QR visual recheck was skipped at owner request |

Older renewal documents say phone installation/UAT were pending because they were written on 29 September. The later LAN 1 October evidence supersedes that **status only**, without changing their technical findings or contract bytes. The 1 October UAT also records that the isolated test server/database/keys were subsequently stopped and deleted. Last reported phone state was paired, pending zero, pointing at the removed home test endpoint `https://192.168.1.5:3443/api/v1`; its pairing label does not imply a reachable server. No office phone enrollment is claimed.

## Remaining acceptance and next actions

1. **Maintain the UI checkpoint:** the owner authorized committing/pushing the
   accepted source, tests, version metadata and documents to the current
   `codex/ui-ux-refresh` branch on 2026-10-20. No merge to main is authorized.
   The unrelated `android/Kimi-Test.code-workspace` is retained locally and
   excluded from Git. The signed 0.9.12+27 candidate and source-snapshot evidence
   remain preserved locally; generated APKs/private signing/runtime data are
   excluded from the source commit.
2. **Close targeted APK gaps if needed:** physical lost-ack replay and interrupted claim/confirmation recovery remain unproved; source-level recovery checks exist. Decide with the owner/LAN PM which additional physical checks are necessary before pilot. Do not repeat passed QR/ordinary-Sync UAT without a specific reason. The enlarged-QR visual recheck was expressly skipped, not passed.
3. **Complete LAN office gates:** LAN owns clean Windows Administrator installation, machine approval, service boot/restart, trusted production browser/phone certificates, reserved-address/subnet/firewall behavior, protected backup/restore, safe update procedure if in release scope, package exclusion review and office acceptance. See LAN [release status](../../LAN/docs/LAN_VERIFICATION_AND_RELEASE_STATUS.md). Implemented helpers and synthetic tests are not proof of those actual office steps.
4. **Prepare field phones:** verify device passcodes, signed APK identity/update path, local worker accounts and authorized fresh QR enrollment to the office backend. The existing home-test pairing must not be treated as an office connection. Worker-phone readiness is a joint rollout task: APK/device preparation plus LAN assistant enrollment and reachable service.
5. **Accept pilot explicitly:** perform bounded office signed-phone Sync/report/renewal checks against the approved office installation, then get owner release/real-data approval. Production use is not established merely by the completed synthetic tests.

No public wire change is requested. Shared base sync v1, QR v1 and renewal v1 fixture bytes/checksums remain authoritative. If a new recovery behavior or payload change is proposed, coordinate both projects and update matching fixtures/tests first. Never uninstall/clear an enrolled phone with unsynced data without the owner's explicit authorization.
