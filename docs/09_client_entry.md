# Client encounter entry

Version 0.4.0+5 adds offline client-record creation from a selected hotspot.

## Worker workflow

1. Open **Hotspots**, select one of the worker's own hotspots, then choose **Enter client record**.
2. Enter the client code. The year starts as the current year, MY is fixed, and enter the final 1–4 digit number. The app adds leading zeroes when saving: entering `4` saves `2026/MY/0004`.
3. Leave the client type as Not specified, choose Old, or choose New. Choosing New opens the new-client details dialog. Its confirmed defaults are PWID, Unknown previous HIV/HCV/HBV, No previous MMT, and No previous ART; gender is optional.
4. Record the test results, supply quantities, DIC referral and optional remark. Tests start as No, which means not tested. Every quantity starts at 0 and must be a whole number of zero or more.
5. Save the record. The same hotspot stays selected and the form resets for the next client.

## Local data rules

- The repository obtains the signed-in worker from the active session. A worker can only create records under their own hotspot.
- The app assigns today's local calendar date. There is no date picker and no backdating.
- A client code may have one active record for the same worker, hotspot and date. The same code can be entered at a different hotspot on that date.
- A save atomically creates the encounter, audit event and future-sync outbox event. Failed saves leave the form in place.

## Current scope and next work

This increment creates client records only. Encounter list/detail, edit/delete controls, daily summary and manual desktop synchronization are separate future increments. The SQLite schema and outbox already preserve the data needed for those later features.
