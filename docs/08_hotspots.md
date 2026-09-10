# Hotspot workflow

Version: 0.3.0+4. Database schema remains version 2; no data-clearing migration is needed.

## Available screens

1. Signed-in home → Hotspots.
2. Your hotspots: searchable by name, scoped to the signed-in worker. Each row shows the hotspot name and assigned peers.
3. New hotspot: name, one or more typed peer fields, Add peer/Remove peer controls, GPS status and Save hotspot.
4. Selected hotspot: saved name, peers and GPS coordinates/status. This is read-only; hotspot editing and client-entry screens remain future work.

The list starts empty if the worker has not created hotspots. Saving returns to the list with a confirmation and clears the search so the new record is visible. Search is case-insensitive for English names and matches literal substrings. Reopening the app loads saved hotspots from SQLite. No demonstration records are added to a phone automatically.

## Creation behavior

- Name is required and trimmed. Peers are typed individually; blank peer fields are omitted, and multiple names are saved in their entered order.
- Opening New hotspot begins one location attempt automatically. Existing-list selection does not capture or modify GPS.
- geolocator 14.0.3 reads current location after checking the phone's location service and runtime permission. The Android manifest requests foreground coarse/fine location only; there is no background location permission or tracking service.
- The attempt has a maximum 20-second budget across service checks, permission response and position acquisition. The native position request also receives the remaining timeout.
- Success displays latitude/longitude and estimated accuracy. Coordinates are saved; accuracy is shown for the current capture only and is not a stored field in this schema.
- Location-off, denied/blocked permission, timeout, platform failure or invalid coordinates show GPS unavailable and allow saving with null coordinates. Real coordinates are never replaced by fabricated 0,0 values.
- Retry GPS explicitly starts a new attempt. Continue without GPS allows skipping a pending result. Any late result from an abandoned attempt is ignored by the form; an already-started native request can run until its bounded timeout.
- Save is disabled while actively locating or saving. Skipping GPS enables save. A successful save writes hotspot, peers, creator/time, audit and outbox records transactionally.
- Database failures retain the form and show a retry message. Back discards an unsaved form. Lock/unlock preserves the form in memory; process termination still loses unsaved drafts.

Reference: [geolocator usage and Android permissions](https://pub.dev/packages/geolocator).

## Ownership and lock boundary

All hotspot pages are internal views beneath the existing session guard; they cannot be pushed above the lock overlay. The repository receives identity from SessionController, and signed-out/locked/background states deny access. Logging out removes the previous worker's workspace. Saving captures the current worker identity; a form never supplies an owner ID.

Search responses are sequenced so a slower earlier query cannot replace a newer result. Async location completion does not save anything by itself. A form disposed on logout ignores late location results.

## Test evidence

Automated coverage includes:

- Granted permission produces the supplied coordinates; disabled location, denied and permanently denied permissions skip acquisition and produce null coordinates.
- Platform failures and invalid positions fall back safely; a stalled attempt finishes after 20 seconds.
- Two hotspots can be created, searched and selected, with peers and coordinates retrieved from real SQLite.
- Missing/explicitly skipped GPS persists as Unavailable with null coordinates; late results cannot change that decision.
- Creation drafts survive lock/unlock, and switching accounts hides the other worker's hotspots.
- Existing database tests cover persistence after close/reopen, ownership and transactional rollback. Existing account tests cover login and inactivity locking.

The GPS gateway is simulated in automated tests. This verifies app logic, not satellite reception or the phone's actual runtime permission dialog. Build/install results are in 05_build_status.md; physical GPS success and failure are tested with the walkthrough below.

## Phone walkthrough

1. Sign in and open Hotspots → New hotspot.
2. With phone location on, allow location permission. Prefer an outdoor position. Enter Hotspot A and two peer names. Wait for Location captured; check the displayed coordinates, then save.
3. Turn phone location off (or deny the app's location permission in phone settings). Create Hotspot B. Confirm GPS unavailable, save, and open the saved record to confirm that status remains.
4. Check both names in the list. Search for Hotspot A, clear the search and select each record to inspect its peers and location status.
5. Close/reopen and sign in again. Both hotspots should remain.
6. Optionally use a different worker account and verify that account cannot see the first worker's hotspots.
7. Restore the phone's location setting after the fallback test if desired.

If GPS cannot obtain a fix where you are, the timeout and retry path still work; a successful real fix remains an outstanding device check until observed. No account password needs to be shared with the developer.
