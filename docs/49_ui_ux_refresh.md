# UI and worker journey refresh

Updated: 2026-10-20. Branch: `codex/ui-ux-refresh`, based on APK checkpoint
`6d36c31496d29d3db92a848138028b9be38a090f`.

## Approved scope and chunks

The owner accepted the **Today first** mockup. This work changes presentation
and navigation only. Preserve repository rules, field values/defaults,
validation, local storage/schema, worker isolation, authentication/lock behavior,
retention and all dashboard pairing/renewal/sync messages and services.

1. Mockups and worker journeys: reviewed; Today first selected.
2. Home and primary navigation: implemented in source; verification below.
3. Hotspot shortcuts and consistent Back: implemented in source; verification below.
4. Client save/edit placement and next-client focus: implemented in source; verification below.
5. Sync presentation and technical-detail grouping: implemented in source; verification below.
6. Form wording and accessibility polish: implemented in source; verification below.
7. Final phone acceptance and signed candidate: complete for this UI scope; see below.

## Chunk 2

- Home now shows the local date and the existing signed-in worker's unique
  people, client records, hotspots visited and HIV-tested totals.
- **Add client record** opens the existing hotspot list. Chunk 3 subsequently
  adds a direct client-entry action beside each hotspot.
- The pending count and last successful sync come from the existing local
  status method. **Open Sync** opens the existing Sync screen; it does not
  upload data. **Full daily summary** opens the existing detailed summary.
- Primary navigation provides Today, Hotspots, Records and Sync inside the
  existing session shell. It is unavailable during active Sync/preparation/test
  actions; child forms and renewal retain their existing navigation.
- Home rereads local totals when returning or unlocking; stale asynchronous
  replies are guarded by the existing worker/session token. Home loading/error
  states retain the Add client action and do not invent zero totals.
- `today_home.dart` is a presentation widget. The workspace calls unchanged
  `todaySummary()` and `syncStatus()` methods; no new connection/status requests
  or automatic upload are introduced. Existing startup trust handling remains.

## Verification and artifact boundary

The first affected widget run exposed test-harness timing/cleanup assumptions:
the old sign-in tests used animation settling without draining native SQLite
I/O, and one new navigation test left an inactivity timer alive. Corrected the
test waits/cleanup without changing authentication or database behavior.

The corrected Home/account/workspace run passed **20/20 tests** across three
suites. Four new Home/navigation checks cover worker-scoped repository totals,
distinct people versus encounter counts, unchanged stored data, no connection
attempts from unpaired local navigation, refresh on return, hidden locked
navigation, and a 320-pixel phone with 1.8x text.

Scoped Dart analysis found no errors or warnings. One pre-existing
`use_null_aware_elements` informational advisory remains in the workspace.
The existing client-entry, ordinary-Sync and renewal screen suites also passed
**20/20 tests**, including exact saved fields, next-client defaults, successful
Sync, saved renewal recovery, lock/Stop and narrow recovery views. Total for this
chunk: **40 passing tests across six suites**. No full-suite or physical-phone
run is claimed. `git diff --check` passed.

This source work is newer than the preserved signed **0.9.11+26** APK. The
existing signed candidate does not contain the UI refresh. No version bump,
APK build, installation, dashboard edit, commit, push or merge occurred in this
chunk. The unrelated `android/Kimi-Test.code-workspace` remains untouched.

## Chunk 3

- Each hotspot has **Add client** and **Details** actions. Entry uses the same
  selected saved hotspot and existing form. Details remain available, including
  the existing hotspot-row tap.
- A successful new-hotspot save passes the ID already returned by
  `createHotspot()` to a confirmation screen. It reads the existing worker-owned
  hotspot back using `hotspots()` and offers **Add client here** or **Return to
  hotspot list**. Loading/retry does not create another hotspot or capture GPS.
- Returning from confirmation clears the old search filter so the saved
  hotspot is visible. Client-entry Back returns to its actual origin: list,
  detail or saved confirmation. Editing Back returns to record detail.
- Forms handle Android Back using their existing saving/session guards and
  invoke the same callback as their visible Back arrow. The workspace delegates
  form Back once, inside the existing lock shell. Persistence rules, resets,
  field defaults, validation and record mutations are unchanged; the new-hotspot
  save callback only carries the already-created ID to the UI.

Eight new journey checks passed: direct entry/details and both Back controls;
single hotspot creation with unchanged coordinates/peers; filtered-list return;
unsaved create/edit navigation without storage changes; 320-pixel/1.8x action
layout; and Back during pending hotspot/create-encounter/update saves.
Local navigation checks observed no connection attempts. Existing Home,
account, hotspot, encounter, ordinary Sync and renewal UI checks also passed:
**48 distinct tests across seven suites** in focused runs. After the final
confirmation-Back adjustment, all eight journey tests passed again.

Scoped analysis found no errors/warnings; only the existing workspace
`use_null_aware_elements` informational advisory remains. Database, auth,
sync/transport, Android and package/dependency files have no diff from the
checkpoint. Client form changes are restricted to Back handling. No APK build,
installation, dashboard edit, commit, push or merge occurred in this chunk.
The later chunk 4 below supersedes the earlier Back-only client-form scope.

## Chunk 4

- One labelled **Save record / Update record** action now sits in a fixed,
  safe-area-aware footer that rises above the keyboard. The separate top Update
  icon was removed. Result/error feedback is beside Save and announced as a
  live region inside the existing session shell.
- The form keeps the existing fields and validators mounted in a single
  scroll view. The same validators run on Save; their first invalid field is
  brought into view. Existing quantity checks and persistence payload/calls are
  unchanged. Failed saves retain inputs; there is no automatic correction.
- Successful creation uses the existing reset values, resets FormField display
  state to match them, scrolls to the start and focuses client number. Focus is
  not requested if the worker is locked/hidden. The next record does not copy
  testing results or supplies from the previous one. Editing still updates the
  same encounter/revision and returns to Today's records.
- Record detail now places the labelled Edit action below the record identity;
  Delete and its confirmation retain their existing behavior.

Verification: **26 tests passed across four focused suites** (existing encounter,
workspace and hotspot journeys, plus five new form-action checks). New checks
cover a fixed Save position during scrolling, a 300-pixel keyboard inset, visible
existing missing-code/quantity errors, successful scroll/focus/default reset,
the exact first/next saved payloads, and duplicate failure retaining inputs with
no additional operation. Existing record-edit validation confirms Edit is
reachable without scrolling and Update preserves the record and revision flow.
The new test harness's focus-node lookup and visibility assertions were corrected;
the completed five-test run passed. Analysis has no new errors/warnings; the
existing workspace informational advisory remains. `git diff --check` passed.

Database, authentication, dashboard/sync/transport, Android and dependency/version
files remain unchanged. These are source/widget checks; no phone installation,
APK build, commit, push or dashboard change is claimed. Next: chunk 5, simplify
Sync presentation while retaining its existing actions and guards.

## Chunk 5

- Sync now leads with the saved pairing state, pending count and last successful
  sync time. A missing receipt time reads **No successful sync yet**; an existing
  timestamp is displayed in local date/time. These are the existing local status
  values, with no new reachability request or inferred successful upload.
- The ordinary **Sync** action precedes secondary renewal and pending-list
  actions. Its existing progress, Stop and exact result messages remain outside
  the technical panel; result updates are announced as a live region.
- **Technical details** starts collapsed and contains local batch preparation,
  debug-only access checking, connection/readiness, retention, pending breakdown
  and app identity. Expanding/collapsing performs no connection or data mutation.
  Sync detail values wrap beneath their labels to fit narrow/large-text screens;
  other summary screens keep their existing layout.
- Unpaired phones retain the QR action/instructions outside the panel. Renewal
  warnings and renewal navigation remain outside it too. The explicitly enabled
  synthetic build retains preparation/review/send outside the panel and still
  has no ordinary Sync action. Build flags, action guards and callbacks are
  unchanged; grouping is not a permission or protocol change.

Verification: **32 distinct tests passed across four focused suites**: three new
Sync presentation checks, ordinary Sync, the existing hotspot/workspace checks,
and the renewal page suite. The three new checks also passed with
`OUTREACH_SYNTHETIC_SYNC_TEST=true` (**35 passing executions** across the completed
runs). They cover collapsed tools, preserved data/no connection on expansion,
unpaired disabled Sync/available QR, 320-pixel/1.8x text layout, and concealment on
lock. Existing checks cover exact acknowledgements/receipt time, pending-list and
preparation behavior, renewal recovery, cancellation, Stop and lock handling.

The first runs exposed lazy-list assumptions in test navigation and a genuine
long-value overflow in technical rows. Scrolling helpers now target the actual
header/control, cleanup occurs before timer checks, and Sync technical values
wrap. Refresh may retain an expanded panel, so the test checks its state before
toggling it. Corrected checks passed; earlier failed runs are not counted as
passes. Scoped analysis has no new errors/warnings after the test-style fix;
the existing workspace informational advisory remains.

The existing Sync/pairing/access/preparation/pending handler block matches HEAD
exactly. Database, auth, sync services/contracts, Android and package/dependency
files have no diff from the checkpoint. `git diff --check` passed. No dashboard
change, APK build, phone installation, commit or push occurred. Next: chunk 6,
form wording and accessibility polish; final phone acceptance remains chunk 7.

## Chunk 6

- Testing dropdowns display **Not tested** for the existing `No` value. Their
  options, defaults, selected state and saved payload values remain unchanged.
  The testing section explains the wording; New/Old help explains the existing
  calendar-year definition. Client-code and hotspot-name help identify existing
  required inputs; peers remain optional and quantities retain their zero default.
- Test-result and quantity controls now have descriptive screen-reader names
  (for example, **HIV test result** and **Distribution 3cc**). Form sections are
  marked as headings. Authentication errors and GPS/hotspot-save feedback use
  live regions; existing password-eye tooltips/actions remain intact.
- Standard text retains the compact three-field supply rows. At larger text
  sizes or restricted widths, supply inputs and client-code fields stack; client
  type segments can turn vertical. Existing controllers, validators, focus,
  selected values and callbacks are reused. Prior-status dialog labels wrap
  above full-width dropdowns, and option rows allow variable height.
- Input helper/error text can wrap onto multiple lines. There are no additional
  mandatory fields, automatic corrections, validation changes or data defaults.

Verification: **34 distinct tests passed across five focused suites** in the
completed runs: encounter entry, encounter actions, hotspot journeys, account
widgets and hotspot/workspace widgets. Three new checks cover screen-reader
names, unchanged `No` persistence and compact rows, 320-pixel/1.8x text with
existing validation and no writes on failure, and large-text new-client dialogs
with exact saved defaults. Existing checks cover create/edit/duplicate saves,
next-client reset, fixed Save/keyboard behavior, busy Back guards, password-eye
behavior, GPS/unavailable fallback and worker isolation.

The first runs exposed test-harness cleanup and lazy-list assumptions: the
semantics handle now closes before the test ends, and hotspot helpers scroll and
settle the final layout before tapping Save. Corrected checks passed; failed
attempts are not counted as passes. Scoped analysis found no issues in the
changed form/app source and tests; `git diff --check` passed.

Before/after hashes match for the existing sign-in submit, client-kind selection,
quantity/save/reset and GPS/hotspot-save handler blocks. Database, authentication
services, dashboard/sync services/contracts, Android and dependency/version
files remain unchanged. This is source/widget verification, not a physical
TalkBack or phone acceptance claim. No APK build/install, dashboard change,
commit or push occurred. Next: chunk 7, final phone acceptance and a signed
candidate after acceptance.

## Chunk 7 — accepted UI and signed candidate

Preparation, 2026-10-20: the owner authorized phone installation/testing with
USB debugging enabled. The connected Android model is `24129RT7CC` with standard
font scale. The regular package is installed; the debug package was not present
at preflight. The signed app is retained. Debug launch uses the existing
`D:/Dev/FlutterPubCache`, `D:/gradle` and `D:/Dev/Android/Sdk` paths, with both
native and Dart synthetic-review flags disabled. No account/database reset or
dashboard change is required for this local UI review.

Phone checklist:

1. Register/sign in to **ANSVK Outreach Test** and review the Today-first home
   and primary navigation.
2. Create/search a synthetic hotspot, use its Add client shortcut and check Back.
3. Enter a synthetic client; inspect New-client details, testing labels,
   distribution/recollection and the fixed Save above the keyboard.
4. Save, confirm next-client reset/focus, open the record and edit it. Check the
   Today totals and saved values.
5. Review the simplified Sync screen and technical toggle without uploading
   records or changing pairing. Existing sync/QR/renewal contracts remain intact.
6. Check a larger-text layout and locked/background concealment, restore any
   temporary device setting, then obtain the owner's UI acceptance.
7. Prepare and inspect a signed candidate after acceptance, record its exact
   identity/checksum and distinguish it from the previous signed APK.

Build, installation, observed phone results and acceptance will be recorded here
as they complete. Preceding widget checks are not physical-phone acceptance.

### Installed debug build and observed phone checks

On 2026-10-20, `flutter run -d <connected phone> --debug --no-pub
--dart-define=OUTREACH_SYNTHETIC_SYNC_TEST=false` completed assembleDebug in
**197.4 seconds**, installed in **10.3 seconds**, and launched successfully.
Native `outreachSyntheticSyncTest` was also explicitly false; the generated
debug BuildConfig confirms false. No source version, dependency or signing
configuration was changed.

| Evidence | Value |
| --- | --- |
| Installed app | ANSVK Outreach Test |
| Package / version | `org.ansvk.ansvk_outreach.debug` / `0.9.11+26` |
| Preserved debug APK | `build/ui-refresh-uat/20261020/ANSVK-Outreach-Test-ui-refresh-0.9.11-26.apk` |
| Size | 121,387,412 bytes |
| SHA-256 | `FA85A372EFF400D902B6CE802919BC05E1CDC61E25156D3FE38535C2691D4DFD` |
| Compiled source snapshot | `build/ui-refresh-uat/20261020/source-sha256.json` |
| Snapshot SHA-256 | `55942BDF7B12EB10CB468840A004A25FBCE512F8C99DE8C9B51CD4F17374547F` |

The owner created a temporary local account and confirmed Today was open.
Direct phone interaction and Android accessibility-tree captures then confirmed:

- Today-first navigation, local zero totals before entry, and no successful sync.
- Creation of synthetic hotspot `UI_UAT_A_20261020` with `SyntheticPeerA`, its
  saved confirmation, Add client here, and Back to the list. Actual location
  capture was available; this run does not claim a GPS-unavailable phone check.
- Required-number validation, then synthetic client `2026/MY/1041` with New
  selected and existing previous-status defaults. Test controls display Not
  tested. Both distribution groups and recollection show three inputs in each
  row at standard text. Distribution 3cc was set to 2; remaining quantities 0.
- Save remains above the keyboard, saves successfully, returns to the top,
  clears/focuses client number and shows the next-client message.
- Records opens the saved client, Edit appears near the heading, client code is
  disabled during edit, and the unchanged edit saves back to Records. Today
  still shows one unique person, one record, one hotspot and zero HIV tests.
- Sync shows four pending test changes, No successful sync yet, QR available,
  ordinary Sync disabled while unpaired, and a collapsed/expandable technical
  panel. No Sync, preparation, QR enrollment or dashboard access-check action
  was triggered. No upload or dashboard change occurred.
- Search for `NO_MATCH` shows No matching hotspots; clearing it restores the
  saved site. Sync was inspected at system font scale 1.8, then the original
  **1.0** was restored and reread. Backgrounding focused the launcher; reopening
  returned to the test app. Manual Lock showed the unlock form and concealed
  hotspot/client content. The existing four-minute timeout was not changed.

Local accessibility-tree evidence is under the ignored `build/ui-refresh-uat/`
directory; it is not committed and may include synthetic data/location. No
screen-capture protection was disabled. This is not a physical TalkBack or a
full visual/contrast audit. No Flutter exception/overflow was observed in the
collected runtime output. Existing business/data/transport source remains
unchanged; `git diff --check` passed.

The owner subsequently replied **Passed — I accept the UI**. The signed
candidate build was then started as **0.9.12+27**, with the source package version
updated accordingly; only version metadata changes beyond the accepted UI.
The source-snapshot file `source-sha256-release.json` has SHA-256
`e7f5934cbe12fd846c0442eef7d768f2276b31fdcb10e993b4e9dc2991085875`.
The completed phone-test Flutter desktop driver was closed; the installed debug
app remained running. The subsequent signed checks are recorded below.
The previous named signed 0.9.11+26 APK was rehashed and remains untouched.
No commit/push/merge has been performed.

### Signed 0.9.12+27 candidate and update

The accepted working tree built successfully with `flutter build apk --release
--no-pub --build-name=0.9.12 --build-number=27
--dart-define=OUTREACH_SYNTHETIC_SYNC_TEST=false`, also setting native
`outreachSyntheticSyncTest=false` for that process. assembleRelease completed in
**170.0 seconds**. The source version and installed-version metadata test now
include 0.9.12+27; both version-reader checks passed. No business-rule, schema,
dashboard/transport, dependency or Android-source changes were made.

| Signed candidate | Verified value |
| --- | --- |
| File | `build/ui-refresh-uat/20261020/ANSVK-Outreach-0.9.12-27-ui-refresh.apk` |
| App / package | ANSVK Outreach / `org.ansvk.ansvk_outreach` |
| Version / build | 0.9.12 / 27 |
| Size | 84,341,490 bytes |
| APK SHA-256 | `9BA9D543C6366987E39D054904293E98DFF02AB7761E7D3E176D8279BF6A2018` |
| Signer SHA-256 | `d1950cfb4e667e15d3c5877d955cbae812b69dcaf3f8d7a23dda284279639dcb` |
| Signature | One signer, APK Signature Scheme v2 verified; same signer as previous release |
| Debuggable / Android backup | false (debuggable omitted in manifest) / false |
| Synthetic review | Dart flag explicitly false; generated release BuildConfig false; disabled-export response retained in DEX |
| Screen capture protection | DEX confirms `0x2000` passed to `Window.addFlags` (`FLAG_SECURE`) |

The exact candidate and `SHA256SUMS.txt`, signature/manifest/native inspection
and source-snapshot evidence are preserved in the ignored build evidence folder.
`apksigner verify --verbose --print-certs` passed. The previous named signed
0.9.11+26 candidate still has SHA-256
`FE1007F8C67FBF52EF78DBCD7C1CE347261F763B56F961626ECC5EE0F265BCA4`.
The generic `build/app/outputs/flutter-apk/app-release.apk` now contains the new
0.9.12+27 bytes; use the named copies to distinguish versions.

After verifying signer and installed version, `adb install -r` updated the
regular app from build 26 to 27 without uninstalling or clearing app data. Android
reported version 0.9.12/build 27 and retained the first-install timestamp
`2026-10-01 00:27:20`. The process launched and reached **Sign in**, retaining the
existing-account entry path. No passwords were requested/shared, and the regular
app was not signed in or synced by the agent. The full local UI journey above
was on the debug Test app; signed-device evidence here is update/launch/package
verification, not another signed dashboard-sync UAT.

**Chunk 7 is complete for the accepted UI scope.** The owner accepted the UI;
the signed candidate is built, inspected, preserved and installed. This does not
change earlier office/real-data deployment gates. Source/docs remain uncommitted
on `codex/ui-ux-refresh`; there was no commit/push/merge. The unrelated workspace
file remains untouched. Final whitespace/protected-source checks passed.

## Owner-authorized Git checkpoint — 20 October

After chunk 7, the owner requested repository housekeeping and committing/pushing
the latest code/documents to the **current `codex/ui-ux-refresh` branch**, expressly
without merging to main. This source checkpoint includes the accepted UI,
0.9.12+27 version metadata, focused tests and current handoff documents.

The unrelated `android/Kimi-Test.code-workspace` is kept locally and excluded
through this checkout's local Git exclusion file. Build output, phone evidence,
APKs, databases, signing material and credentials remain ignored; no generated
or private artifact is part of this source commit. The preserved signed APK and
compiled-source snapshot were rechecked before staging: artifact hash matches
the table above and there are no application-source snapshot mismatches. No
application code changed during this housekeeping, so earlier tests/build/phone
acceptance still apply; they were not repeated without a new code change.

Use `git log -1`, branch tracking and the GitHub branch for the resulting commit
and push status. Earlier statements about uncommitted work describe their
respective pre-checkpoint stages. No merge to main is part of this checkpoint.
