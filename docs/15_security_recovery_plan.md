# Security and recovery plan

Status: accepted planning decision, 14 September 2026.

This plan records the safety decisions needed before ANSVK Outreach can be used with real client information. The current APK is still a development build. It stores data locally, works offline, and does not have real dashboard sync yet.

## Current user direction

Privacy is higher priority than recovering unsynced phone data.

If a worker forgets the password, or if a phone is locked/damaged/lost, the project accepts that unsynced records may be lost. We should not create a password bypass, admin unlock, technical data extraction path, or recovery feature that could expose client records to an unauthorized person.

Password recovery is suspended for the first pilot.

Confirmed review answers:

- Password recovery remains suspended for the first pilot.
- Worker phones must have a device passcode before using the app.
- The data assistant approves starting again when unsynced data may be lost.
- The future dashboard should warn when a phone has not synced for 3 days.
- The data assistant can mark a phone as lost or retired in the dashboard.

## Why this plan is needed

The app is designed for offline field work. That means the phone may contain unsynced client records. Recovery choices must protect two things at the same time:

- client privacy if a phone is lost or accessed by the wrong person
- unsynced records if a worker forgets a password or a phone is damaged

For this project phase, client privacy wins when these two goals conflict. The app must not solve password recovery by weakening privacy.

## Current protection already implemented

- Workers use local username/password accounts.
- Passwords are not stored as plain text.
- Password verification uses PBKDF2-HMAC-SHA256 with random salt.
- Workers can only view, edit and delete their own local records through the app.
- The app locks after one minute of inactivity.
- The app hides content when backgrounded or locked.
- Android screenshots/recent-app snapshots are blocked with secure-window protection.
- Android backup is disabled in the manifest.
- Credential material is not included in audit or future sync payloads.
- SQLCipher database opening is implemented in code, using a generated local passphrase stored through secure storage.

Phone migration and user data visibility checks passed for the development APK.

## Current limitations

- SQLCipher database opening is implemented and passed migration testing on the user's existing phone test database.
- Real dashboard sync is not active in the APK yet.
- Retention cleanup is not implemented yet.
- Password recovery is not implemented and should remain suspended for now.
- Password change is not implemented.
- There is no approved export/recovery tool for locked unsynced records.
- If the app is uninstalled or phone app data is cleared, unsynced records can be lost.

## Decisions to lock before real-data pilot

### 1. Password recovery is suspended

Confirmed decision: do not build password recovery, admin unlock, technical data extraction, password bypass or data-assistant recovery code in the APK for the first pilot.

Reason: live dashboard recovery is not available yet, and no approved safe recovery design exists. The project prefers losing unsynced phone data over exposing client information to an unauthorized person.

Worker guidance should say: if the password is forgotten, unsynced data on that locked phone may be lost. The worker should report the issue before starting again.

### 2. Forgotten password handling

Confirmed decision:

1. If the worker is still signed in, they should not sign out until pending work is handled.
2. If the worker is locked out, there is no password bypass.
3. The app should not expose local records through a recovery screen.
4. The project may allow starting again with a fresh account/app state, accepting that old unsynced data is lost.
5. The data assistant is the role allowed to approve starting again when unsynced data may be lost.

Suspended options:

| Option | Current status | Reason |
| --- | --- | --- |
| Data-assistant recovery code | Suspended | Dashboard does not exist, and recovery code could become a password bypass if designed poorly |
| Technical recovery of locked phone data | Suspended | Could expose client records to someone other than the signed-in worker |
| Password reset that preserves local records | Suspended | Requires a stronger security design before it can be trusted |

Allowed future discussion: after the dashboard and encryption design exist, the project can reconsider a safer recovery design. Until then, no recovery feature should be implemented.

### 3. Lost or stolen phone

Recommended procedure:

1. Worker reports lost phone immediately.
2. Treat unsynced records on that phone as possibly lost.
3. When dashboard device management is enabled, data assistant marks that device as lost.
4. Do not accept future sync from that device ID unless reviewed.
5. Review dashboard to see the latest successful sync time for that worker/device.

The APK already has a generated device ID for future dashboard tracking.

### 4. Damaged phone

Recommended procedure:

1. If the phone can still open the app and the worker can sign in, preserve the data and sync first once real sync exists.
2. If the worker cannot sign in or the app cannot open, do not attempt technical data extraction under the current plan.
3. Replace or re-enroll the worker phone if needed, accepting that unsynced records may be lost.
4. When dashboard sync history is enabled, use dashboard last-successful-sync records to identify the possible data gap.

### 5. Database encryption

Recommended decision: database encryption remains a pre-pilot requirement for real client information.

Reason: app-private storage and screen lock reduce ordinary access, but they do not provide the same protection as encrypting the database contents.

Implementation should be a separate technical work package. It must include:

- library/package selection
- key storage design
- migration from existing unencrypted development database
- performance check on target phone
- backup/recovery behavior
- test that app update preserves existing data

Do not claim the development build is safe for real client information until this work is implemented and verified.

### 6. Backup policy

Recommended decision: Android cloud backup stays disabled.

Reason: the app stores sensitive local outreach information. It should not silently copy client data to a personal cloud backup account.

Future dashboard sync is the planned official copy of records. The dashboard should become the long-term full-history store after successful sync.

### 7. Phone passcode and device handling

Recommended operational rule: each worker phone should have a device passcode or biometric lock enabled before pilot use.

Confirmed decision: worker phones are required to have a device passcode before using the app.

Recommended worker rules:

- Do not share phone unlock code.
- Do not share app password.
- Lock the app before handing the phone to anyone else.
- Report lost phone immediately.
- Understand that forgotten passwords may cause unsynced data loss.
- Do not ask anyone to bypass the app password.

### 8. Dashboard-side account/device control

The dashboard recovery workflow should support:

- paired device list
- device status: active, lost, retired
- worker list
- last successful sync per worker/device
- warning when a phone has not synced for 3 days
- sync rejection if a device is lost or not paired
- visible warning when a worker has pending/late sync
- data-assistant-only action to mark a phone as lost or retired

The dashboard must not receive or store APK password verifier material.

## Recovery behavior matrix

| Situation | Worker action | Data assistant action | Data rule |
| --- | --- | --- | --- |
| Forgot password, still signed in | Do not sign out; report before continuing | Data assistant decides whether to keep using, sync later, or restart after accepting data loss | Do not add password bypass |
| Forgot password, locked out | Report the issue | Data assistant approves re-enroll/start again only if data loss is accepted | Unsynced data may be lost |
| Phone lost | Report immediately | Data assistant marks device lost in dashboard when available | Records after last sync may be missing |
| Phone damaged | Report whether app can still open | Data assistant approves replace/re-enroll if needed; no technical extraction under current plan | Unsynced data may be lost |
| Wrong dashboard address | Clear or replace saved address | Confirm correct local address | No data leaves phone until paired/upload exists |
| Worker leaves project | Sync first when available; otherwise report pending work | Retire worker/device after accepted sync or accepted data-loss decision | Dashboard keeps synced history |

## Implementation backlog from this plan

1. Confirm fresh encrypted install behavior on phone before pilot packaging.
2. Add any additional technical tests needed after phone findings.
4. Add worker-facing warning text that password recovery is suspended and unsynced data may be lost if the password is forgotten.
5. Keep password reset/recovery out of the APK until a future approved design exists.
6. Add dashboard device states: active, lost and retired.
7. Add data-assistant-only dashboard/device workflow for accepted data-loss re-enrollment.
8. Verify on representative phones before real-data pilot.

## User review answers

Confirmed on 14 September 2026:

1. Password recovery remains suspended for the first pilot.
2. Workers' phones are required to have a device passcode before using the app.
3. The data assistant approves starting again when unsynced data may be lost.
4. The future dashboard should show a warning when a phone has not synced for 3 days.
5. The data assistant can mark a phone as lost or retired in the dashboard.

## Current project rule

Do not use the APK with real client information.

Do not add password reset, password bypass, technical data extraction, automatic cleanup, or production sync behavior until the related security/recovery decision is approved.

