# Pre-pilot readiness checklist

Status: draft for review, 15 September 2026.

This checklist defines what must be true before the ANSVK Outreach APK is used with real client information. It separates the current Android APK from the Windows LAN Outreach foundation so the pilot decision does not accidentally assume live sync exists.

## Current APK state

Current Android increment: `0.9.3+18`.

Current SQLite schema version: `6`.

Implemented and phone-tested on the user's connected device:

- Local worker registration and sign-in with username/password.
- One-minute inactivity lock and background concealment.
- Device-passcode warning before account use.
- Password recovery suspended warning.
- Worker-owned data access through the app.
- Searchable local hotspot list.
- Hotspot creation with typed peer names and GPS fallback.
- Client encounter form with structured `YYYY/MY/0000` code input.
- Daily summary, including unique people by client code.
- Today's records list, detail, edit and delete.
- Local audit/outbox tracking for future sync.
- Sync Status with pending-operation counts.
- Future dashboard address, pairing-code and certificate-fingerprint preparation.
- Retention safety status with cleanup disabled.
- SQLCipher database opening for Android builds.

The APK still has no active real Windows dashboard connection. It cannot upload records, receive acknowledgement, mark operations synced, or safely clean old client records.

## Pilot decision options

### Option A: Development testing only

Use the APK only with synthetic or dummy records. This is the current safest state.

This option is ready now.

### Option B: Local-only field pilot before live dashboard sync

Use the APK on worker phones for real outreach entry before live dashboard sync is enabled and verified.

This is possible only if the project accepts these limits in writing:

- Records remain only on each worker's phone.
- There is no verified office backup or full-history desktop copy from those phones yet.
- If a phone is lost, damaged, reset, uninstalled, or the worker forgets the password, unsynced records may be lost.
- Old client records will not be deleted automatically because dashboard acknowledgement does not exist.
- Data assistant review/reporting across workers cannot happen yet.

This option needs explicit project acceptance before use.

### Option C: Full pilot with dashboard sync

Use the APK with real client information and office desktop history.

This option is not ready because live phone-to-dashboard pairing, upload, acknowledgement and cleanup are not implemented and verified end to end yet.

## Required checks before any real-client pilot

| Area | Required check | Status |
| --- | --- | --- |
| Release build | Create a release-signed APK, not a debug-signed APK | Release APK `0.9.3+18` built and manually installed on one phone |
| App version | Confirm version shown/recorded for handover | Release artifact `0.9.3+18` recorded in 05_build_status.md |
| Worker phones | Test install/update on every pilot phone model | One release APK phone test passed; all worker phones still needed |
| Device passcode | Confirm every worker phone has a device screen lock | Policy agreed; field verification needed |
| Worker accounts | Confirm each worker creates their own account on their own phone | Policy agreed; field verification needed |
| Password handling | Confirm workers understand no password recovery | Policy agreed; training needed |
| Data loss handling | Confirm data assistant process for lost phone/forgotten password | Policy agreed; written procedure needed |
| Offline entry | Confirm hotspot/client/daily/today flows with worker training data | Core flows tested; worker training needed |
| Privacy | Confirm no cross-worker access through normal app UI | Automated tests pass; multi-phone pilot check needed |
| Database protection | Confirm SQLCipher migration/fresh install on pilot phones | One development phone passed; pilot phones needed |
| Sync | Confirm real dashboard pairing/upload/acknowledgement | Certificate check and offline pairing prep implemented; live pairing/upload/acknowledgement not active |
| Retention cleanup | Confirm cleanup only after dashboard acknowledgement | Status-only implemented; cleanup disabled |
| Reporting | Confirm office review/reporting workflow | LAN Outreach foundation exists; office workflow not verified with phone data |

## Minimum phone test script before handover

Run this on each pilot phone using dummy records first:

1. Install the release candidate without clearing app data if upgrading.
2. Open the APK and confirm the device-passcode warning is shown before account use.
3. Register or sign in as that phone's worker.
4. Create one hotspot with at least two peer names.
5. Create one client record using the structured client code input.
6. Create a second record for the same client code at a different hotspot, if a second hotspot exists, and confirm Daily summary counts one unique person.
7. Edit one record and confirm the change appears in Today's records.
8. Delete one dummy record and confirm it disappears from Today's records and Daily summary.
9. Lock or wait one minute and confirm the app hides data until the password is entered.
10. Open Sync Status and confirm pending changes are visible, real sync is unavailable, and Retention safety shows cleanup disabled.
11. Close and reopen the app and confirm saved dummy data remains visible after sign-in.

## Dashboard handover documents

A future dashboard developer must read these files before building the desktop side:

- [01_plan.md](01_plan.md)
- [02_implementation_plan.md](02_implementation_plan.md)
- [03_decisions_and_tracking.md](03_decisions_and_tracking.md)
- [04_development_specification.md](04_development_specification.md)
- [06_local_database.md](06_local_database.md)
- [09_client_entry.md](09_client_entry.md)
- [10_daily_summary.md](10_daily_summary.md)
- [11_today_records.md](11_today_records.md)
- [12_sync_architecture_decision.md](12_sync_architecture_decision.md)
- [13_dashboard_api_contract.md](13_dashboard_api_contract.md)
- [15_security_recovery_plan.md](15_security_recovery_plan.md)
- [16_database_encryption_plan.md](16_database_encryption_plan.md)
- [18_release_signing_plan.md](18_release_signing_plan.md)

## Current recommendation

Keep the current APK in development/pilot-preparation status until release signing and the all-phone dummy-data test are complete. The release-signing setup plan is documented in 18_release_signing_plan.md.

Do not use it for real client information as a full program system until the Windows dashboard can receive data and acknowledge exact operations from the APK. If the project chooses a local-only pilot before live sync, document that decision separately and train workers on the data-loss limits before deployment.

