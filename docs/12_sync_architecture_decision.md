# Sync architecture decision

This document locks the planned communication design between the Android APK and the future Windows office dashboard. The dashboard does not exist yet, so this is a contract and boundary document, not an implemented sync feature.

The detailed endpoint and JSON contract is documented separately in [13_dashboard_api_contract.md](13_dashboard_api_contract.md).

## Decision

The Android APK will sync directly with a Windows desktop dashboard over the office local network.

The communication channel will be:

`Android APK -> local Wi-Fi or phone hotspot network -> Windows dashboard HTTPS device API`

The dashboard will run a small local server while it is open. The phone will send queued changes to that local server only when the worker taps Sync.

The current joint contract uses a separate HTTPS device API for phones:

`https://<office-server-ip>:3443/api/v1`

The existing browser dashboard may remain on `http://<office-server-ip>:3000` for synthetic integration UAT only. Before real Outreach reporting is shown through the browser dashboard, the PM must either migrate browser traffic to HTTPS or formally accept and document the remaining HTTP risk.

No cloud server, Google Drive, email, Bluetooth, USB file copy, phone-to-phone sync, or automatic background sync is part of this plan.

## Why this design

This keeps the workflow simple for the office:

- The worker brings the phone to the office.
- The phone and Windows computer join the same local network.
- The dashboard is opened on the Windows computer.
- The worker taps Sync in the APK.
- The dashboard receives and stores the data.

This design also protects the current offline-first requirement. Workers can keep entering records without network access. Sync is only a later transfer step.

## Roles

The Android APK is responsible for:

- Saving worker-owned data offline in SQLite.
- Keeping a queue of unsynced operations.
- Sending only the signed-in worker's queued operations during manual sync.
- Retrying the same operation IDs if sync is interrupted.
- Marking operations as synced only after the dashboard confirms durable receipt.
- Keeping unsynced records indefinitely.
- Removing old synced client records only after successful acknowledgement and retention rules allow it.

The Windows dashboard is responsible for:

- Running the local API service while the dashboard is open.
- Receiving sync batches from phones.
- Validating worker/device identity.
- Saving all accepted operations into the desktop database.
- Preserving full history.
- Returning acknowledgements for accepted operations.
- Returning clear rejection reasons for invalid operations.
- Producing reports and account-management tools in the separate dashboard project.

## Connection discovery

For the first production-ready version, use a simple manual connection method.

The dashboard should display:

- Office computer name.
- Phone sync API address, such as `https://192.168.1.20:3443/api/v1`.
- Full certificate SHA-256 fingerprint for APK verification.
- A pairing code or QR code.

The APK should allow the worker or data assistant to enter or scan that connection information. After pairing, the APK can remember the dashboard address.

Automatic dashboard discovery can be added later, but it should not be required for the first sync implementation.

## Pairing and trust

The phone should not send data to any random computer on the network. Before first sync, the APK and dashboard should pair.

Minimum pairing design:

- Dashboard shows a six-digit one-time pairing code.
- APK user enters or scans the code.
- APK verifies the dashboard certificate fingerprint before sending the request.
- A valid code pairs the phone immediately and returns a hidden device credential.
- APK stores the paired dashboard identity, certificate fingerprint and device credential in secure storage.

For development, the important rule is: do not silently send client data to an unpaired or untrusted address. Unexpected certificate changes must block sync until an approved rotation or re-pairing process is completed.

## Sync payload

The APK already stores operations in an audit/outbox model. Sync should send operations, not a loose spreadsheet-style dump.

Each sync batch should include:

- Protocol version.
- APK schema version.
- Project ID.
- Batch ID.
- Device ID.
- Worker ID.
- App version.
- Operation list in audit sequence order.

The APK stores future project/device metadata locally in schema version 3:

- `project_id`: `ansvk_outreach`
- `project_name`: `ANSVK Outreach`
- `device_id`: generated once on the phone
- `created_at`: UTC creation timestamp

Workers do not type this information. The app creates it automatically during database setup or upgrade, and future sync code should include it in the sync batch header.

Each operation should include:

- Operation ID.
- Entity type: worker, hotspot, or encounter.
- Entity ID.
- Revision.
- Action: create, update, or delete.
- Occurred timestamp.
- Payload.

The dashboard must treat operation IDs as idempotent. If the same phone retries the same operation after a timeout, the dashboard should not create duplicate records.

Current limits are 100 operations and 1 MiB JSON per upload batch. Each upload request has a 30-second timeout. After the initial request, the APK may make at most three foreground retries after approximately 5, 15 and 30 seconds, with visible progress and a Stop action.

## Acknowledgement rule

The phone may mark an operation as synced only when the dashboard replies that the exact operation ID and revision were accepted and durably saved.

If the dashboard receives only part of a batch, only those accepted operation IDs should be acknowledged. The remaining operations must stay pending on the phone.

The phone must not delete or clean up client records just because it attempted sync. Cleanup is allowed only after acknowledgement and retention rules pass.

## Error handling

Expected sync states:

- Not configured: no dashboard is paired yet.
- Dashboard not reachable: phone cannot connect on the local network.
- Sync in progress: phone is sending a batch.
- Partially synced: dashboard accepted some operations and rejected or missed others.
- Sync successful: all pending operations were acknowledged.
- Sync failed: no operation was safely acknowledged.

The APK should show these states plainly. It should not show a successful sync unless the dashboard actually acknowledged the operations.

## Data direction

For the current project scope, sync is upload-only:

`phone -> dashboard`

The phone should not download other workers' client records. This preserves the requirement that workers see only their own records.

The only future download candidates are non-client reference data, such as approved hotspot lists or account/pairing configuration, and those should be handled as separate dashboard features.

## Dashboard build guidance

When the Windows dashboard project starts, build it around these components:

- Local database for full history.
- Separate HTTPS device API for phone sync.
- Pairing/phone approval screen.
- Worker/account management screen.
- Sync review/log screen.
- Reporting screens.

The dashboard should be the long-term source of full history. Phones remain field-entry devices with local offline storage and limited retention.

## What not to build in the APK yet

Until the dashboard API exists, the APK should not implement real upload, fake success, or data cleanup.

The APK now has a Sync status screen that shows:

- Pending operation count.
- Pending operation breakdown and a detail list of operation type/action/revision/time.
- Sync readiness: address saved, pairing code saved, ready to request pairing, dashboard paired and ready-to-sync state.
- Retention safety: 7-day keep window, old client-record count, records held because unsynced, records eligible after acknowledgement and cleanup disabled state.
- Last successful sync, usually Never for now.
- Desktop connection status: Not configured.
- A disabled Sync button or an explanatory message.

The APK also has a local dashboard connection row in SQLite. It starts as Not configured and is reserved for future dashboard address/pairing information. The APK can save a dashboard address and pairing code locally, but this only prepares a later pairing request. It is not pairing and does not allow upload yet.

This prepares the user workflow without pretending that dashboard sync is already available.

## Locked decisions

- Sync is manual, not automatic.
- Sync is local network, not cloud.
- Sync is phone to Windows dashboard.
- Dashboard stores full history.
- Phone only marks operations synced after dashboard acknowledgement.
- Phone never receives other workers' client records.
- Old client records can be removed from phone only after successful sync and retention rules.
