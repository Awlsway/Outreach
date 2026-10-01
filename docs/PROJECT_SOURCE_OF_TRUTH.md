# Outreach APK source of truth

Updated: 2026-10-01. Owner: Outreach APK PM. Start here when continuing the Android project in a new chat. This index explains authority and reading order; it does not itself approve a production rollout.

## Read first

1. [APK current state](APK_CURRENT_STATE.md) for checked architecture, worker workflow, decisions and source/artifact versions.
2. [APK verification and release status](APK_VERIFICATION_AND_RELEASE_STATUS.md) for dated evidence, known limits, Git state and next gates.
3. The relevant detailed APK source, contract and test document below before changing that area.
4. For dashboard/server or office deployment work, the separate `D:/LAN/docs/PROJECT_SOURCE_OF_TRUTH.md`, `LAN_CURRENT_STATE.md` and `LAN_VERIFICATION_AND_RELEASE_STATUS.md`.

Check `git branch`, `git status` and source versions again; this index is a dated handoff, not a substitute for the working tree.

## Ownership and precedence

| Source | Owns |
| --- | --- |
| This index | APK reading order and document ownership |
| `APK_CURRENT_STATE.md` | Current APK behavior, architecture and approved scope |
| `APK_VERIFICATION_AND_RELEASE_STATUS.md` | Verification, signed artifact provenance, uncommitted state and open APK/field gates |
| `lib/`, `android/`, `pubspec.yaml` | Implemented Android behavior and package version; report differences from approved contracts |
| [Core plan](01_plan.md), [development specification](04_development_specification.md), [security/recovery](15_security_recovery_plan.md) | Owner requirements and decisions; old “future” wording may now be historical |
| [Database](06_local_database.md), [client entry](09_client_entry.md), [daily summary](10_daily_summary.md), [today's records](11_today_records.md) | Detailed phone fields and workflows |
| [APK dashboard API contract](13_dashboard_api_contract.md), LAN `Outreach_LAN_API_Technical_Contract_v1.md` and `docs/fixtures/outreach/v1/` | Base v1 operation/sync shapes and acknowledgement; later approved contracts supersede obsolete pairing prose |
| [QR pairing v1](36_qr_pairing_v1.md), LAN `36_qr_pairing_v1.md` and matching `qr-v1` fixtures | QR-only enrollment, five-minute expiry and current pairing policy |
| LAN `37_certificate_renewal_contract_v1.md` and mirrored `certificate-renewal-v1` fixtures | Initial trust, signed renewal grant, claim/receipt/confirmation and recovery bounds |
| [Certificate validation](41_certificate_validation.md), [initial trust](43_initial_certificate_trust.md), [renewal QR](44_certificate_renewal_qr_review.md), [transition](45_certificate_renewal_transition.md), [Sync navigation](46_certificate_renewal_sync_navigation.md) | Bounded APK design and implementation evidence |
| [Android package check](47_certificate_renewal_android_build.md), [signed candidate](48_certificate_renewal_signed_candidate.md), LAN `Outreach_Phone_Renewal_UAT_2026_10_01.md` | Dated build and joint physical-phone evidence; read the latest status file for current interpretation |

Approved contracts define required behavior; source defines implemented behavior; evidence defines what was actually verified. A mismatch is a gap to investigate, not permission to silently change wire bytes. APK local database schema 9, sync payload schema 6 and LAN database migration 8 are independent. QR v1 supersedes manual pairing instructions in older plans/base contract; “manual Sync” still means the worker taps Sync. Renewal v1 supersedes informal certificate-rotation prose. Do not treat dated “pending” text in a subchunk document as current after later evidence.

The LAN team owns Windows installation, machine approval, HTTPS/browser/phone service, device admission, reporting and backup. This repository owns the Android offline worker flow, local storage, QR scanner, device-side trust and Sync. The APK's `client_code` must never be joined to MIS `CCode`.

## New-chat starting prompt

```text
Read docs/PROJECT_SOURCE_OF_TRUTH.md, APK_CURRENT_STATE.md and
APK_VERIFICATION_AND_RELEASE_STATUS.md. Check the actual branch, working tree,
source version and signed artifact before work. Read the relevant shared
contract and LAN source-of-truth documents for cross-project changes.
Distinguish implemented code, tested artifact, and office release acceptance.
Preserve accepted QR/sync/renewal wire contracts and existing phone data unless
the owner explicitly authorizes a reset. Report a verified discrepancy before
changing either project. My next task is: <describe one chunk>.
```

Update the owning current-state/status file after a behavior or acceptance change, with date and evidence. Keep credentials, private keys, pairing QR contents and real client data out of documents. No production deployment or data reset is implied by this handoff.
