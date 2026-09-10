# ANSVK Outreach decisions and delivery tracking

Updated: 10 September 2026.

## Current status

M1 is complete as a planning baseline. SQLite schema version 2, accounts/locking, and hotspot search/creation with typed peers and GPS fallback are implemented. Hotspot tests cover simulated GPS, saved data, search, lock/draft preservation and worker isolation. GPS success/fallback persistence has been confirmed from the user's phone database. Database encryption/recovery remain pre-pilot work. Client-entry screens and production sync remain unimplemented. Final verification and device evidence are tracked in 05_build_status.md.

| Milestone | Status | Evidence / next action |
| --- | --- | --- |
| M1 Requirements | Complete (planning baseline) | Requirements, acceptance checks, field dictionary and explicit defaults documented |
| M2 Foundation | In progress | SQLite schema v2 and password verifiers implemented; database encryption/recovery remain pending |
| M3 Accounts/hotspots | Complete for development increment | User confirmed hotspot phone results; read-only database verification passed; see 05_build_status.md and 08_hotspots.md |
| M4 Encounters | Not started | Depends on M3 and field decisions |
| M5 Summary | Not started | Depends on M4; D02 resolved |
| M6 Sync preparation | Not started | Depends on M4; desktop integration remains external |
| M7 Pilot/release | Not started | Requires completed implementation and real-device evidence |

## Open decisions

The entries below preserve the original questions. 04_development_specification.md now supplies working defaults for D01, D03–D05, D07 and D09–D12, plus password unlock in D06. These defaults are project-manager decisions, not user confirmations, and no longer block development. Password recovery, storage protection and real-device verification remain pre-pilot work.

| ID | Decision | Proposed handling | Needed by |
| --- | --- | --- | --- |
| D01 | New/Old initial selection | No preselection; allow an unspecified value to respect the client-code-only mandatory-input rule. Confirm whether every encounter instead needs this classification | M4 |
| D03 | Gender default | No preselection; optional rather than silently assigning a gender | M4 |
| D04 | Testing and referral defaults | Testing No (not tested); referral No | M4 |
| D05 | Retention boundary | Keep today and the six preceding local calendar dates; purge older eligible data only after acknowledgement | M6 |
| D06 | Unlock and forgotten password | Password unlock; choose a recovery design that does not erase unsynced data. Recovery remains unresolved pending account design | M3 / before pilot |
| D07 | Unavailable GPS | Null latitude/longitude with Unavailable status; never fabricate a real coordinate | M3 |
| D08 | Phone compatibility | Obtain Android versions and one representative device; choose minimum supported version during technical evaluation | M2 |
| D09 | Existing form layout | Design from the confirmed fields unless a paper/Excel reference is supplied | M1; nonblocking |
| D10 | Client-code comparison | Trim surrounding whitespace, preserve leading zeros; clarify letter-case handling if alphanumeric codes are used | M2 / M4 |
| D11 | Calendar and clock | Use phone local date for visits; retain original date when editing; document that offline clock correctness cannot be guaranteed | M2 / M6 |
| D12 | Summary labels | Distinct visited hotspots, HIV tested excludes No, and separate totals per supply type | M5 |

## Confirmed decisions to preserve

- D02 resolved: clients served counts unique people, using distinct client codes for the signed-in worker's active encounters today across all hotspots. Multiple visits count once; deletion removes a person from the total only when no active encounter remains that day.

- Four workers, own phones, English, offline self-registration with username/password.
- Own records only; workers may create/edit/delete their own encounter records.
- Inactivity lock after one minute.
- Typed multiple peers; searchable hotspots; no hotspot editing in this phase.
- GPS only at hotspot creation, with fallback permitted.
- Client identity is worker-scoped; same client/hotspot/day duplicate prevention confirmed.
- Same client can visit different hotspots that day; no backdated new visits.
- New is first visit in the calendar year; Old does not load historical client information.
- Exact category choices/defaults are recorded in 01_plan.md.
- Manual future LAN sync; no other workers' records downloaded.
- Seven-day client retention only after successful sync; hotspots remain; desktop retains history.
- Windows dashboard is a separate project.

## Risks and responses

| Risk / dependency | Response | Owner role |
| --- | --- | --- |
| Desktop service is not yet available | Preserve all unsynced data; deliver contract and development tests; label production sync as pending | Project manager / future desktop implementer |
| Storage grows while no sync is available | Show pending counts and failures; assess realistic volume during pilot; never silently delete unsynced records | Mobile implementer |
| Lost phone, forgotten password or uninstall before sync | Resolve recovery and storage protection design before pilot; explain local-data limitations in worker guide | Project manager / mobile implementer |
| Same username created independently on different phones | Use generated worker/device IDs; define reconciliation with desktop team | Mobile and future desktop implementers |
| Duplicate rules bypassed by rapid saves or edits | Enforce storage constraint and atomic transactions; verify with A08 | Mobile implementer |
| Latest edit lost during stale acknowledgement or cleanup | Track revisions, acknowledge individually, and test cleanup against latest state | Mobile implementer |
| Device time/date differs from actual outreach date | Store timestamps and visit date consistently; test midnight and clock changes; settle policy before cleanup | Mobile implementer |
| Summary accidentally counts visits instead of unique people | Apply confirmed D02: distinct client codes per worker/day across hotspots; verify repeat visits, edits and deletions with the summary fixture | Mobile implementer |

## Next work package

Hotspot implementation and phone database verification are complete for this increment. The next separate feature is client encounter entry under the selected hotspot, including the New-client modal and existing duplicate rules. Database encryption/recovery remain pre-pilot requirements. No client-entry or desktop work is included in this hotspot increment.
