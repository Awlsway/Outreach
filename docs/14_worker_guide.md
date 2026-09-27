# ANSVK Outreach worker guide

This guide explains the current Android APK behavior for outreach workers and the data assistant. The app works offline on the phone. Ordinary manual Sync is implemented for development testing; production deployment is not yet approved.

## First use and sign in

1. Open the app.
2. Confirm the phone has a device screen lock or passcode.
3. If this is first use on the phone, create your account with a username and password.
4. Remember the password. The app does not have password recovery in the pilot, and unsynced records may be lost if you cannot sign in.
5. After registration or sign in, the home screen shows the signed-in username at the bottom.

The app locks after four minutes of inactivity. Unlock with the same password. You can also use the lock button at the top of the home screen.

## Hotspots

Open **Hotspots** from the home screen.

To create a hotspot:

1. Tap **New hotspot**.
2. Let the app try to capture GPS.
3. Enter the hotspot name.
4. Enter one or more peer names if needed.
5. If GPS is unavailable, continue without GPS.
6. Tap **Save hotspot**.

Hotspots are saved on the phone under the signed-in worker account. Workers can only see their own hotspots. Hotspot editing is not available in this phase.

## Client records

Open **Hotspots**, select a hotspot, then tap **Enter client record**.

Client code uses this format:

`YYYY/MY/0000`

The app helps enter this by keeping `MY` fixed and padding the final number. For example, entering `4` saves `2026/MY/0004`.

Only client code is required before saving. Other fields can stay at their defaults if not available.

For client type:

- **Not specified** is allowed.
- **Old** does not load previous information.
- **New** opens the additional client information dialog.

Testing choices:

- **No** means not tested.
- **Non reactive** and **Reactive** both count as tested.

Distribution and recollection quantities must be whole numbers of zero or more.

After saving a client record, the same hotspot remains selected and the form resets for the next client.

## Daily summary

Open **Daily summary** from the home screen.

The summary counts only the signed-in worker's active records for today on this phone. It shows:

- Hotspots visited.
- Total client records.
- Unique people by client code.
- DIC referrals.
- New, Old and Not specified client totals.
- Tested and Reactive totals.
- Distribution totals.
- Recollection totals.

A client who appears at two hotspots on the same day counts as two records but one unique person.

## Today's records

Open **Today's records** from the home screen.

The list shows today's active client records for the signed-in worker. Tap a record to view details.

From the detail screen, the worker can:

- Edit the record.
- Delete the record.

Delete is a soft delete. The record disappears from active views and summary, but a delete change remains pending for future dashboard sync.

## Sync status

Open **Sync status** from the home screen. For first enrollment, ask the data assistant to show **Add phone** on the dashboard and scan its QR. Address, certificate trust and enrollment code come from that QR; there is no manual-entry fallback.

In ordinary builds, connect the phone to the same office network as the dashboard and tap **Sync** once. The app verifies dashboard access, then sends your pending changes in order. It shows batch progress and retries temporary connection failures at most three times per request. Tap **Stop** to stop the current attempt. Confirmed changes remain confirmed; unconfirmed changes stay pending for a later manual Sync. Locking or leaving the app also stops the run.

After completion, check **Pending changes** and **Last successful sync**. An empty-queue check sends no records and does not change the previous successful-sync time. Rejected changes stay pending; ask the data assistant to review them. Revoked or retired phones cannot upload. Never uninstall the app just to solve a connection problem, because unsynced records can be lost.

The screen also shows connection details, pending change types, app/project identity and retention safety. After successful Sync, old client records are removed only when the dashboard has confirmed every revision. Today and the previous six dates remain. Records without complete confirmation are kept; hotspots remain on the phone and the dashboard keeps full history. Check retention for the last check, removed and held counts. The optional **Prepare changes locally** action only validates and reviews data; it does not send anything. Private export and reviewed-test sending controls exist only in explicitly configured synthetic test builds.

## Important limitations

- Do not use this development build for real client information yet.
- Ordinary Sync passed synthetic phone testing; pilot/release gates remain.
- Local cleanup requires complete dashboard confirmation; unsynced or uncertain records are retained.
- Password recovery is not implemented.
- Database encryption is enabled in Android builds, but recovery remains suspended for the first pilot.
- Uninstalling the app or clearing app data can remove unsynced local records.
