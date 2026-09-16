# ANSVK Outreach worker guide

This guide explains the current Android APK behavior for outreach workers and the data assistant. The app works offline on the phone. Real dashboard sync is still unavailable in the APK.

## First use and sign in

1. Open the app.
2. Confirm the phone has a device screen lock or passcode.
3. If this is first use on the phone, create your account with a username and password.
4. Remember the password. The app does not have password recovery in the pilot, and unsynced records may be lost if you cannot sign in.
5. After registration or sign in, the home screen shows the signed-in username at the bottom.

The app locks after one minute of inactivity. Unlock with the same password. You can also use the lock button at the top of the home screen.

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

Open **Sync status** from the home screen.

This screen is for checking pending changes and future dashboard setup only. Real sync is not active yet because this APK has not completed controlled live pairing, upload, acknowledgement or cleanup.

The screen shows:

- Pending changes count.
- Pending change breakdown.
- Whether a dashboard address is saved.
- Whether a pairing code is saved.
- Whether a certificate fingerprint is saved.
- Whether the phone is ready to request pairing later.
- Whether the phone is paired.
- Whether sync is ready.
- Retention safety counts for old client records.
- App/project/device identity for future support.

**Ready to sync** remains **No** in this version.

The **Retention safety** section shows whether old client records exist on the phone. Cleanup remains disabled until a verified dashboard acknowledgement flow exists.

The **Pending changes** screen shows operation type, action, revision and time. It does not show full client payload details.

The **Dashboard pairing** screen can save or clear a future local dashboard API address, six-digit pairing code and certificate SHA-256 fingerprint. This is preparation only in the current APK. When real sync is implemented, the phone sync address must use HTTPS on port 3443, for example:

`https://192.168.1.50:3443/api/v1`

The **Check certificate** button can test whether the dashboard HTTPS certificate matches the entered SHA-256 fingerprint. This check does not pair the phone, upload data, acknowledge data or delete records.

Saving pairing information stores the address, six-digit code and approved fingerprint for later setup only. It does not pair the phone, upload data, acknowledge data or delete records.

The APK code can prepare the future pairing request format and understand future pairing responses internally, but there is still no worker action that sends it to a dashboard or marks the phone paired.

## Important limitations

- Do not use this development build for real client information yet.
- Real dashboard sync is not active in this APK.
- The app will not remove old client records until real dashboard acknowledgement exists.
- Password recovery is not implemented.
- Database encryption is enabled in Android builds, but recovery remains suspended for the first pilot.
- Uninstalling the app or clearing app data can remove unsynced local records.

