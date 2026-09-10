# ANSVK Outreach — core project plan

## Confirmed requirements (updated after clarification)

These requirements take precedence over the original notes below.

### Scope and accounts
- English-only Android APK for four workers, each with their own phone; operates offline.
- Workers self-register with a username and password on first use.
- Workers can view, edit, and delete only their own records on their own phone.
- Audit who creates, edits, and deletes records.
- Lock after one minute of inactivity.
- The Windows office dashboard is a separate future project. Plan its connection and synchronization interface only in this phase. A data assistant will manage accounts, review data, and generate reports there. Desktop exports are out of scope.
- Project-manager technology decision: Flutter/Dart with SQLite; see 04_development_specification.md for rationale and implementation defaults.

### Hotspots
- Select existing hotspots from a searchable list.
- New hotspots store name, typed peer names (multiple allowed), GPS, creation date, creator user ID, and a generated hotspot ID.
- Capture GPS only at creation. Allow proceeding with placeholder GPS information if unavailable.
- Hotspot name and peer editing are deferred to a later phase.
- Keep hotspot information on the phone permanently under the current retention policy.

### Encounters and validation
- Client codes are entered manually and required before saving.
- A client code identifies the same person within one worker's records. Codes can overlap across workers.
- Prevent duplicate active records for the same worker, client code, hotspot, and calendar day, including when editing.
- Allow that client to have encounters at different hotspots on the same day.
- Record visits for today only; no backdated entry.
- New means the client's first visit during the calendar year. Workers select New or Old manually.
- Old clients do not need their previous information loaded.
- New clients open the additional-information modal described below.

| New-client field | Choices | Default |
| --- | --- | --- |
| User type | PWID, PWUD, SPOUS, MSM, FSW, FM, Youth, Other | PWID |
| Gender | Male, Female | Not specified |
| Previous HIV testing status | Unknown, Positive, Negative | Unknown |
| Previous HCV status | Unknown, Positive, Negative | Unknown |
| Previous HBV status | Unknown, Positive, Negative, Vaccinated | Unknown |
| Previous MMT status | No, Drop Out, Current | No |
| Previous ART status | No, Defaulter, Current | No |

- HIV, HCV, HBV, and syphilis testing choices: No (not tested), Non reactive, Reactive.
- Distribution: 3cc, 1cc, LDS, alcohol swabs, sterile water, condoms.
- Recollection: 3cc, 1cc, LDS.
- Quantities are non-negative whole numbers, defaulting to zero.
- Refer to DIC is Yes/No only. Include a remark field.
- Client code is the explicitly required input. Do not introduce additional mandatory user inputs without resolving their defaults or optional handling.
- Save opens a blank encounter form; Back returns to today's summary.

### Summary
- Header: ANSVK Outreach. Footer: signed-in account name. Bottom button: data entry.
- Show today's hotspot total, clients served, HIV tested, and distribution totals.
- Confirmed: clients served counts unique people, calculated as distinct client codes among the signed-in worker's active encounters for today across all hotspots. A person visiting multiple hotspots counts once. Deleted encounters are excluded; a person remains counted while another active encounter exists that day.
- Proposed interpretation for other totals: distinct hotspots visited, Non reactive plus Reactive HIV results for HIV tested, and distribution totals separately by supply type.

### Future sync and retention
- Sync only when the worker manually taps Sync while connected to the office LAN.
- Upload the worker's own data; do not receive other workers' records.
- Desktop retains the full history.
- Remove client information and encounters older than seven days only after successful synchronization. Keep unsynchronized older data and retain hotspots.

Proposed integration design to finalize with the separate desktop project:
- Stable generated IDs for workers, devices, hotspots, encounters, and audit operations; client codes are worker-scoped identifiers.
- Versioned LAN API with desktop pairing and authentication.
- Local queue for creates, edits, and deletions, recording actor, timestamp, record ID, and revision.
- Idempotent retries and per-operation acknowledgements to avoid duplicates and data loss during interrupted or partial sync.
- Keep deletion information until acknowledged by the desktop.
- Purge eligible older client data only after its latest changes and related audit operations are acknowledged. Include client-identifying audit payloads in retention cleanup.
- Show pending changes, progress, last successful sync, and failures.
- Finalize API schema, account reconciliation, conflict handling, and desktop discovery before implementing connectivity. Until a desktop service exists, do not claim successful uploads or purge data as though it was uploaded.

### Remaining design details
- Whether an existing paper or Excel form should guide the layout; no reference supplied yet.
- Unlock method: password unlock was proposed.
- Missing GPS representation: empty coordinates with an explicit Unavailable status was proposed.
- Defaults for gender, New/Old, testing results, and DIC referral.
- Exact seven-day cutoff and handling of device clock changes.
- Password recovery and reconciliation of self-created accounts with future desktop management.
- Label clients served clearly as unique people.

## Original project notes

this is the core document for this project.

I want to create an android apk.
I don't know which coding language can create that apk.
that app will used by 4 outreach workers.
So user login will need.
they will use offline only.
apk should record which user add or edit or delete which record.
data from apk will sync to office desktop when phone connect to office LAN network.
data on phone will only keep last 7 days.
User will go outreach and open the apk with their account.
user will reach to summary page.
user click on data entry button which will lead to data entry page.
on data entry page,
they see 2 choice "Old hotspot" or "new hotspot".
they click on new hotspot button and apk collect current location GPS and user type in
name of hotspot, assigned peers and click on proceed button.
apk will create a record to a table named hotspot as name, assigned peer, GPS data, created date and userID who created that record. that table will give a hotspotID.
when user click on proceed button, user will see a form for data input.
in that form user can enter
client code,
New or Old, if user choose "new" , there will be a floating modal will open and ask to fill a form - user type, gender, Previous HIV testing status, Previous HCV status, Previous HBV status, Previous MMT status, Previous ART status
Testing HIV which will let user to choose from "no", non reactive, reactive
Testing HCV which will let user to choose from "no", non reactive, reactive
Testing HBV which will let user to choose from "no", non reactive, reactive
Testing Syphillis which will let user to choose from "no", non reactive, reactive
Distribution_3cc,Distribution_1cc,Distribution_lds,Distribution_alcohol swab,Distribution_sterile water, Distribution_condom,
Recolleciton_3cc, Recolleciton_1cc, Recolleciton_lds,
refer to DIC,
remark,

at the footer, user can click on save record.
after that a new record will save and user see a new blank form to fill. if user click on back button, user will reach to a summary page which will show aggregate data of input data for today. footer of that summary page will show signed in user account name. header of summary page will show "ANSVK Outreach" title. there will be a button on the button of page which will lead to data entry page.
