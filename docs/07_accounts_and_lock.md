# Offline accounts and inactivity lock

Account increment: 0.2.1+3. SQLite schema version: 2. Hotspot screens were subsequently added in 0.3.0+4; see 08_hotspots.md.

## Implemented behavior

- First use opens Create your account. Existing accounts open Sign in after app restart.
- Registration accepts a trimmed, case-sensitive username (1–64 characters), a password (8–128 characters), and matching confirmation. Passwords are not trimmed.
- Registration Password and Confirm password fields have independent eye buttons; Sign in has an eye button for Password. All start hidden. Toggling preserves typed text and switches the accessible Show/Hide label. Visibility resets when switching forms or submitting. Password unlock continues to use a hidden field.
- Successful registration signs the worker in. A second local account can be created from the sign-in page, with a distinct worker identity.
- Login and password unlock work entirely offline. A successful login creates only an in-memory session; restarting the process requires login again.
- Signed-in home shows the username, manual lock and logout controls. Hotspot/client screens remain outside this change.
- One minute without input locks the session. Touch activity resets the deadline while foregrounded and unlocked. Returning from another app does not reset the deadline.
- Background/inactive state immediately covers the app and blocks repository access. Returning after the deadline requires the password. The signed-in subtree remains mounted behind the lock to support future in-memory drafts.
- A pending authentication result cannot restore a session after logout/disposal.
- Five failed attempts trigger a persisted 30-second cooldown for that account. Unknown accounts and wrong passwords return the same generic message.
- Android FLAG_SECURE prevents screenshots and recent-app snapshots of the app. This is additional UI protection, not database encryption.

## Credential storage and upgrade

Migration 1 → 2 adds credentials linked to workers; it does not recreate existing tables. The table stores the algorithm, salt, verifier, work factor, failure count and cooldown. No plaintext password is stored.

PBKDF2-HMAC-SHA256 uses 600,000 iterations, a random 32-byte salt per account, and a 256-bit verifier. Hashing runs in an isolate to keep the UI responsive. Verification compares the derived bytes without returning on the first mismatched byte. Registration saves the worker profile, credentials, audit entry and outbox operation in one transaction. Credential material never enters audit snapshots or pending sync payloads.

References: [OWASP password storage](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html), [cryptography PBKDF2 API](https://pub.dev/documentation/cryptography/latest/cryptography/Pbkdf2-class.html), [Flutter lifecycle states](https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html).

The older profile-only database API cannot create a usable login. Existing test/legacy profiles without credentials remain intact and cannot authenticate; the production preview seeded no such profiles. Do not attach a password to an existing identity merely because someone supplies its username.

## Source files

- lib/auth/password_hasher.dart: password derivation and comparison.
- lib/auth/auth_service.dart: registration, verification and stored cooldown.
- lib/auth/session_controller.dart: identity, timeout, lifecycle access checks and logout.
- lib/app.dart: registration/login, account home and lock forms.
- lib/database/schema.dart: additive credential migration.
- Android MainActivity: secure-window flag.

## Validation

Code analysis passes. All 19 tests pass: existing database coverage plus registration rollback, credential exclusion from audit data, wrong/unknown login, cooldown persistence, migration/reopen, owner isolation, background timeout, successful form submission, confirmation mismatch, logout/login, and the exact 60-second lock timer. The real production hasher is tested separately for unique salts and correct/incorrect password verification; UI/service tests use a test-only fast hasher.

Phone installation and launch evidence is recorded in 05_build_status.md. Automated tests are not a claim that the user has completed their phone walkthrough.

## Phone walkthrough

1. Create your account and remember its password.
2. Check the signed-in username at the bottom.
3. Leave the app untouched for one minute, then unlock with the password.
4. Use Sign out, then sign in again.
5. Close/reopen the app and confirm it asks you to sign in.
6. Send it to the background for over one minute and verify the lock on return.

## Remaining work

Password recovery and password changes are not implemented. There is no destructive reset button. Do not uninstall or clear app data as a recovery method for unsynced records.

The SQLite database is app-private but not encrypted at rest. Full data-storage protection and recovery remain pre-pilot requirements. Debug signing and debug access also mean this build is for development, not live client information. Hotspot screens, encounters, summary UI and desktop sync are separate future work.
