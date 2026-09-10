# ANSVK Outreach implementation plan

Planning baseline: 10 September 2026.

Requirements source: [01_plan.md](01_plan.md). Open decisions and working defaults: [03_decisions_and_tracking.md](03_decisions_and_tracking.md).

## Objective and release boundary

Deliver an installable English-only Android app for four outreach workers using their own phones. Workers must register, sign in, record and manage their own outreach encounters, and see today's totals without internet access.

The first release includes local change tracking and a documented future synchronization contract. Production desktop synchronization depends on the separate Windows dashboard project. No successful sync or automatic retention cleanup may be simulated in the released app. Without a real desktop acknowledgement, older unsynchronized records remain on the phone.

Out of scope: Windows dashboard implementation, desktop exports, other workers' data sharing, hotspot editing, backdated entry, automatic sync, and additional languages.

## Delivery sequence

| Milestone | Work packages and deliverables | Depends on | Exit criteria |
| --- | --- | --- | --- |
| M1: Requirements baseline | Screen flow, field dictionary, validation rules, summary definitions, decision log | Existing requirements | Every confirmed requirement has a work package and acceptance check; unresolved choices are explicitly marked |
| M2: Technical foundation | Technology decision, Android compatibility target, app scaffold, local schema, migrations, storage and credential design | M1; device information for compatibility | App installs on a representative phone; local data survives restart; ownership and duplicate constraints are demonstrated |
| M3: Accounts and hotspots | Offline self-registration, login/logout, inactivity lock, searchable own-hotspot list, creation and GPS fallback | M2 | Accounts work offline; isolation holds; one-minute lock works; hotspot creation succeeds with and without location |
| M4: Encounter workflow | New/Old forms, defaults, quantity validation, save/reset, own-record list, edit/delete and audit history | M3 | Complete offline create/edit/delete flow passes; duplicate rule holds on edits and rapid saves; audit changes are atomic |
| M5: Daily summary | Daily hotspot, unique clients served, HIV-tested and supply totals; summary navigation | M4 | Known sample data yields exact totals; clients deduplicate by client code across hotspots; edits/deletes update totals; other accounts and other days are excluded |
| M6: Future sync preparation | Persistent change queue, revision tracking, draft API contract, acknowledgement and retention logic tested using a development-only fake service | M4 | Retry, interruption and cleanup checks pass in development; production app cannot mark data synced without a real acknowledgement |
| M7: Pilot and APK handover | Release APK, version information, installation guide, worker guide, test evidence, known limitations and desktop integration handover | M3–M6; target phones available | Representative phone testing and worker walkthrough complete; release blockers resolved; user accepts pilot behavior |

M5 and M6 can be scheduled independently after M4. This describes dependencies, not a request for parallel agents. Dates will be set after the technology, available development effort, and target devices are known; no delivery dates are committed yet.

## Screen deliverables

1. First-use registration and subsequent login.
2. Lock screen that conceals client information and allows password unlock (working default).
3. Today's summary with ANSVK Outreach title, signed-in username and data-entry button.
4. Hotspot choice: searchable existing list and new-hotspot action.
5. New-hotspot form with typed peer names and GPS availability indicator.
6. Encounter form with new-client modal, testing, quantities, referral and remarks.
7. Own-record list and detail view with edit/delete actions, needed to deliver the confirmed management permissions.
8. Sync status entry point showing pending changes and the unavailable desktop connection honestly until integration is configured.

Saving an encounter returns a blank client form under the selected hotspot as a working default. Back from the encounter flow returns to the summary. Preserve an in-progress form across inactivity locking; discard it only through an explicit navigation choice or successful save.

## Data design brief for M2

- Worker: generated ID, username, secure password verifier and creation timestamp. Never store a plaintext password or include password material in audit payloads.
- Hotspot: generated ID, owner worker ID, name, typed peers, nullable coordinates, location status and creation timestamp.
- Encounter: generated ID, owner, hotspot ID, client code, local visit date, New/Old selection, new-client fields, tests, quantities, referral, remark, timestamps and revision.
- Audit operation: operation ID, actor, entity ID, action, timestamp and revision; enough change information for desktop history, subject to the client-data retention policy.
- Pending synchronization: operation state and acknowledged revision. A newer local edit must remain pending even when an earlier revision is acknowledged.

Client demographics belong to the encounter where collected; an indefinitely retained client directory is not required. Enforce ownership in data access and writes, not only by hiding UI controls. Enforce the active-record uniqueness key in storage: worker + client code + hotspot + visit date. Save the record mutation, audit operation and pending change in one transaction.

Editing an older retained record must preserve its original visit date. No editable visit-date field is provided. Deleting a record removes it from active lists and totals while retaining pending deletion information until acknowledged.

The technology decision is documented in 04_development_specification.md: Flutter/Dart with SQLite. SDK health, exact package versions, storage security and release builds remain foundation work.

## Acceptance checklist

Use synthetic client information during development and testing.

| ID | Check | Expected result |
| --- | --- | --- |
| A01 | Register, restart, log in and enter a visit in airplane mode | All work without internet; saved data survives restart |
| A02 | Access another local account's records through list, detail, update and delete paths | Access denied; own records remain accessible |
| A03 | Leave an open client form inactive for 60 seconds; also background and return after the timeout | App is locked and sensitive content concealed; unlock restores the draft |
| A04 | Create hotspot with GPS available, unavailable, or permission denied | Valid location stored when available; fallback allows proceeding; generated ID and creator stored |
| A05 | Search existing hotspots and inspect available actions | Own matching hotspots selectable; name/peer editing unavailable |
| A06 | Select New and then Old | New modal exposes exact choices/defaults in 01_plan.md; Old does not load prior client information |
| A07 | Save empty code, negative quantity or fractional quantity; then save valid input | Invalid input rejected; valid record saved once; quantities default to zero |
| A08 | Save same worker/code/hotspot/day twice, including double-tap and conflicting edit | Second active encounter prevented with understandable feedback |
| A09 | Save same code on a different hotspot today or on the next day; use same code under another worker | Allowed without violating account isolation |
| A10 | Save, edit and delete own encounter | Audit identifies actor/action; totals update; deleted record leaves active views |
| A11 | Try to backdate a new encounter; edit an earlier retained encounter | No backdate entry; editing preserves original visit date |
| A12 | Save an encounter and press Back from the next blank form | Form resets after save; Back reaches summary with title and account footer |
| A13 | Verify summary fixture below | Exact agreed totals; only current worker and local day counted |
| A14 | Interrupt a local write or restart with queued changes | No partial record/audit state; pending operations persist |
| A15 | Development fake service receives a retry, partial acknowledgement, or stale-revision acknowledgement | No duplicate effects; unacknowledged/latest edits stay pending |
| A16 | Run development retention checks around cutoff | Only eligible acknowledged client data removed; hotspots and unacknowledged changes retained |
| A17 | Open Sync in release before desktop integration exists | Clear unavailable status; no fabricated success, acknowledgement or cleanup |
| A18 | Install and update the release build on representative worker devices | App launches; update preserves accounts/data; offline and lock flows work |

Summary fixture: for one worker today, create two encounters for client A at hotspots X and Y, and one encounter for client B at X. Set HIV results to Non reactive, Reactive and No. Set 3cc distribution to 2, 3 and 0. Expected: 2 hotspots, 2 unique clients served, 2 HIV tested and 5 units of 3cc. Add another worker's record and yesterday's record; neither affects today's totals. Delete B's encounter: clients served becomes 1, and X remains counted because A still has an active encounter there. Then delete A's encounter at X: clients served remains 1 because A still has an encounter at Y. Delete A's last encounter: clients served becomes 0. In a fresh copy of the fixture, edit B's code to C: clients served remains 2; editing B's code to A at X must be rejected by the duplicate rule.

## Desktop integration handover

Provide the future desktop team with a versioned contract covering:

- Pairing, endpoint configuration, authentication and worker/device identity reconciliation.
- Upload payloads for hotspots, encounters, edits and deletions, including IDs, revisions and audit history.
- Parent dependencies, idempotency keys, durable per-operation acknowledgements, rejected operations and retry behavior.
- Conflicts between later mobile edits and any future desktop edits; server acknowledgement must mean durable storage.
- Timeout, unavailable server and interrupted network behavior.
- Retention eligibility and an explicit ban on clearing unacknowledged changes.

Production integration and end-to-end sync verification become a subsequent deliverable once the desktop service exists. Development fake-service checks do not establish production sync readiness.

## Release gate and management cadence

The implementer supplies work and test evidence; the project manager tracks scope, dependencies, risks and acceptance; the user decides business rules and accepts the pilot. These are responsibilities, not assignments to additional agents.

At each milestone, update status, completed deliverables, evidence, outstanding decisions and the next action in 03_decisions_and_tracking.md. Changes to confirmed behavior must be reflected in the requirements and their acceptance checks. Do not mark work complete solely because files or screens exist.

Release blockers: data loss, unauthorized cross-account access, broken offline entry, incorrect duplicate enforcement, incorrect agreed totals, failure to lock, or cleanup before durable acknowledgement. Fix these before pilot handover. Document lesser usability issues with an owner and disposition.
