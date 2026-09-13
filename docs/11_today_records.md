# Today's records

The phone app now includes a Today's records screen from the signed-in home page. It lists only the current worker's active local records for today's visit date.

Each list row shows:

- Client code.
- Hotspot name.
- Client type, including Not specified.
- A compact test summary.
- Saved time from the local record timestamp.

Tapping a row opens a Record detail screen. It shows client information, testing, distribution, recollection, DIC referral, saved time and remark.

The detail screen can delete a record after confirmation. Delete is a soft delete: the record is hidden from Today's records and Daily summary, while a delete operation remains in the audit/outbox tables for future sync.

The detail screen can also open Edit record. Edit reuses the client-entry form with client code locked and the original hotspot/visit date unchanged. Workers can update client type, New-client details, tests, quantities, DIC referral and remark. A successful edit writes an update operation to the audit/outbox tables for future sync.
