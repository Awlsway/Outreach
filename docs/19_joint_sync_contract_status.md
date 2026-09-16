# Joint sync contract status

Updated: 15 September 2026.

This document records the current joint APK and LAN Dashboard sync contract. It is a planning and handover record only. No real network sync implementation has started in the APK.

## Current joint draft documents

The APK-side contract is [13_dashboard_api_contract.md](13_dashboard_api_contract.md).

The LAN-side technical contract is maintained in the LAN project at:

```text
D:\LAN\docs\Outreach_LAN_API_Technical_Contract_v1.md
```

The LAN-side security and operations draft is maintained at:

```text
D:\LAN\docs\Outreach_LAN_Security_Operations_Design.md
```

The accepted byte-identical v1 synthetic fixture bundle is stored in this repository at [fixtures/outreach/v1](fixtures/outreach/v1). It was copied from:

```text
D:\LAN\docs\fixtures\outreach\v1
```

Future dashboard developers should read these alongside the APK data and workflow documents listed in [13_dashboard_api_contract.md](13_dashboard_api_contract.md).

## Locked communication model

The dashboard has two separate local listeners during the pilot:

| Purpose | Address pattern | Status |
| --- | --- | --- |
| Browser dashboard | `http://<office-server-ip>:3000` | Allowed for synthetic integration UAT only |
| Phone sync API | `https://<office-server-ip>:3443/api/v1` | Required for real APK sync |

The browser dashboard login and the paired-phone device credential are separate authentication boundaries. A LAN browser session must never be accepted by the device API, and a phone device credential must never be used as a browser login.

Plain HTTP is prohibited for real phone sync. Before real Outreach reporting is shown in the browser dashboard, the PM must either move browser traffic to HTTPS or formally accept and document the remaining HTTP risk with network controls.

## Locked protocol values

| Field | Value |
| --- | --- |
| `api_version` | `1` |
| `protocol` | `ansvk-outreach-sync` |
| `protocol_version` | `1` |
| `project_id` | `ansvk_outreach` |
| Initial APK `schema_version` | `6` |

Unsupported versions must fail clearly. All pending APK operations must remain safely stored on the phone.

## Locked pairing and device rules

Pairing codes are exactly six digits, expire after 10 minutes, allow at most five incorrect attempts, permit one successful use only, and can be cancelled while unused by LAN Admin, Officer, or Assistant.

Creating a pairing code in the dashboard is the explicit approval. When the APK submits a valid code over the trusted HTTPS device API, the phone pairs immediately and receives its device credential. No second approval screen is required.

The APK-generated `worker_id` is preserved. Successful pairing creates a provisional Outreach worker on LAN. The first matching revision-1 `worker/create` operation confirms that worker.

Only one active device is permitted per `worker_id`. Phone replacement requires revocation or retirement of the prior device, followed by re-pairing. Historical accepted data remains on the dashboard.

The device credential is an opaque bearer credential with at least 256 bits of entropy. LAN returns it once after successful pairing. The APK stores it in Android secure storage and sends it automatically for device API calls. It must never be displayed, logged, stored in SQLite, or included in audit payloads. LAN stores only a verifier or hash.

## Locked certificate and secret rules

The phone sync API requires HTTPS plus full certificate SHA-256 fingerprint pinning. During pairing, staff compare the LAN-displayed fingerprint with the APK before the APK sends the pairing request.

If the certificate changes unexpectedly, the APK must block sync. It must not silently trust the new certificate. Recovery requires approved certificate rotation or device revocation and re-pairing.

Planned certificate rotation uses an overlap window: the dashboard shows both fingerprints, the APK stores both approved fingerprints temporarily, and the old fingerprint is removed after successful sync through the new certificate.

Phone secure storage holds the SQLCipher key, pinned certificate fingerprint, and device credential as separate values. None of these values may be written to APK SQLite tables, audit operations, screenshots, or normal logs.

## Locked sync batch rules

Each upload request has a 30-second timeout. After the initial request, the APK may do at most three foreground retries after approximately 5, 15, and 30 seconds. The sync screen must show progress and a Stop action. Stopping or exhausting retries leaves all unacknowledged records pending.

Each upload batch is limited to 100 operations and 1 MiB JSON. The APK must split larger pending queues into additional batches. Oversized unaccepted records remain pending with a clear error; nothing is deleted from the phone.

`operation_id` is the idempotency key. Identical retries return the original acknowledgement. Reusing an operation ID with conflicting content is rejected and audited.

Partial batch acceptance is allowed. The dashboard acknowledges only operations that are durably committed. The APK may mark only those exact `operation_id` and `revision` values as acknowledged.

Empty batches should use `/sync/status`, not upload an empty `/sync/batches` request.

More than five minutes of difference between phone time and LAN server time creates a warning, but does not reject otherwise valid records or rewrite `visit_date`.

## Locked role boundaries

Admin and Officer can review current Outreach data, summaries, device/sync status, audit history, and support-only `client_code`.

Assistant can review current Outreach data and summaries, and can manage pairing, revocation, and retirement. Assistant cannot see audit history or `client_code`.

Guest has no Outreach access.

LAN cannot edit synchronized service records.

## Locked storage and operations boundaries

LAN stores Outreach SQLite at:

```text
C:\ProgramData\KSC_Dashboard\outreach\outreach.db
```

LAN stores Outreach backups under:

```text
C:\ProgramData\KSC_Dashboard\outreach-backups
```

The installer creates both locations, grants the dashboard runtime account required access, verifies read/write access, and preserves them during updates.

Server records are not automatically deleted during the pilot. Manual deletion requires Admin approval, verified backup, and an audit entry. Server retention does not inherit the APK's seven-day phone cleanup rule.

## Permanent separation from MIS and LMIS

Outreach APK data, MIS data, and LMIS data remain permanently separate.

APK `client_code` is never linked to MIS `CCode`. Outreach data must not contribute to MIS KPIs, targets, validation, reconciliation, client search, or LMIS workflows.

The dashboard may show Outreach reports in its own Outreach module, but it must not mix Outreach client records into MIS/LMIS storage or reporting logic.

## APK implementation boundary

The current APK may keep showing saved HTTPS dashboard address, six-digit pairing-code preparation and certificate fingerprint preparation, but those fields are not real pairing yet.

Before real APK sync implementation starts, the APK sync UI and networking code must follow this joint contract: HTTPS port 3443, certificate fingerprint pinning, pairing-code exchange for a hidden device credential, explicit acknowledgement tracking, retry limits, and safe cleanup only after exact acknowledgement and seven-day retention.
