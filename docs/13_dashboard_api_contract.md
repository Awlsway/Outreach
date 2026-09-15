# Dashboard API contract

This document describes the planned API between the Android APK and the future Windows dashboard. The dashboard is not implemented yet. This is the handover contract that future dashboard development should follow so the APK and dashboard can sync without changing business rules later.

## Reference documents for the dashboard developer

Read these documents before designing the dashboard database, screens or API:

1. [01_plan.md](01_plan.md) — confirmed business requirements, field choices, retention rules and sync scope.
2. [02_implementation_plan.md](02_implementation_plan.md) — milestone boundaries, acceptance checks and desktop integration handover expectations.
3. [03_decisions_and_tracking.md](03_decisions_and_tracking.md) — current status, confirmed decisions, risks and next work package.
4. [04_development_specification.md](04_development_specification.md) — field dictionary, local storage rules and implementation defaults.
5. [06_local_database.md](06_local_database.md) — phone-side SQLite tables, audit/outbox model and migration notes.
6. [09_client_entry.md](09_client_entry.md) — client record workflow and validation behavior.
7. [10_daily_summary.md](10_daily_summary.md) — phone-side summary definitions, including unique people.
8. [11_today_records.md](11_today_records.md) — own-record list/detail/edit/delete behavior.
9. [12_sync_architecture_decision.md](12_sync_architecture_decision.md) — locked sync architecture and boundaries.

The dashboard developer should treat this file as the detailed API contract, and the files above as the business and data context behind it.

## Contract source of truth

This contract is based on the current APK SQLite schema version 5 and repository behavior in app version `0.9.1+16`.

The phone stores pending sync data in `audit_operations` and `sync_outbox`.

`audit_operations` has these columns:

| Field | Type / meaning |
| --- | --- |
| `sequence` | Local integer order assigned by SQLite |
| `operation_id` | Generated UUID, unique and stable for retry |
| `actor_id` | Worker ID that performed the action |
| `entity_type` | `worker`, `hotspot`, or `encounter` |
| `entity_id` | ID of the worker, hotspot, or encounter |
| `revision` | Entity revision for this operation |
| `action` | `create`, `update`, or `delete` |
| `occurred_at` | UTC timestamp |
| `payload` | JSON string stored locally; API sends it as a decoded JSON object |

`sync_outbox` tracks which `operation_id` values are still pending. A future sync implementation should select unacknowledged rows from `sync_outbox`, join to `audit_operations`, decode `payload`, and send operations in `sequence` order.

## Communication model

The APK syncs to the dashboard over the office local network only.

`Android APK -> office Wi-Fi or phone hotspot network -> Windows dashboard local HTTP API`

The dashboard must run a local HTTP API while it is open. The APK sends data only when the worker manually taps Sync. There is no cloud server, automatic background sync, USB file copy, email transfer, Google Drive transfer or phone-to-phone sync in the current plan.

## API version

Use API version `v1` for the first dashboard implementation.

Recommended base URL pattern:

`http://<dashboard-local-address>:<port>/api/v1`

Example:

`http://192.168.1.20:8080/api/v1`

The dashboard should display its current local address and port on screen so the data assistant can pair phones.

## Required dashboard endpoints

### Health check

`GET /api/v1/health`

Purpose: let the APK confirm that it reached an ANSVK dashboard, not a random local server.

Example response:

```json
{
  "ok": true,
  "service": "ansvk-dashboard",
  "api_version": 1,
  "dashboard_name": "Office dashboard",
  "server_time": "2026-09-12T08:30:00Z"
}
```

### Pairing request

`POST /api/v1/pairing/requests`

Purpose: register or approve a phone/device before it can sync client data.

Example request:

```json
{
  "api_version": 1,
  "project_id": "ansvk_outreach",
  "project_name": "ANSVK Outreach",
  "device_id": "8c8df2a3-8f46-4f1f-98e6-a2c7f8cbb801",
  "device_created_at": "2026-09-12T07:00:00Z",
  "worker_id": "65d24c79-807e-45a4-ae3b-719214ed8d3e",
  "username": "worker1",
  "pairing_code": "123456",
  "app_version": "0.9.1+16",
  "requested_at": "2026-09-12T08:35:00Z"
}
```

Example success response:

```json
{
  "ok": true,
  "paired": true,
  "dashboard_id": "office-dashboard-001",
  "dashboard_name": "Office dashboard",
  "paired_device_id": "8c8df2a3-8f46-4f1f-98e6-a2c7f8cbb801",
  "paired_at": "2026-09-12T08:35:20Z"
}
```

Example rejection response:

```json
{
  "ok": false,
  "paired": false,
  "error_code": "invalid_pairing_code",
  "message": "Pairing code was not accepted."
}
```

The exact pairing security can improve later, but the first real sync must not silently send data to an unpaired dashboard.

### Sync batch upload

`POST /api/v1/sync/batches`

Purpose: upload queued phone operations to the dashboard. The APK should send operations in local audit sequence order.

Field names in this request must match the current APK fields. Do not rename them in the dashboard API.

Batch header fields:

| Field | Source / meaning |
| --- | --- |
| `api_version` | API version; first version is `1` |
| `protocol` | Fixed protocol label, recommended `ansvk-outreach-sync` |
| `batch_id` | Generated UUID for this send attempt |
| `project_id` | From APK `app_identity.project_id`; currently `ansvk_outreach` |
| `project_name` | From APK `app_identity.project_name`; currently `ANSVK Outreach` |
| `device_id` | From APK `app_identity.device_id`; generated once per phone database |
| `device_created_at` | From APK `app_identity.created_at` |
| `worker_id` | Signed-in worker sending the batch |
| `app_version` | APK version/build string |
| `batch_created_at` | UTC timestamp when the batch was created |
| `operations` | Pending operations from `audit_operations` joined to `sync_outbox` |

Example request:

```json
{
  "api_version": 1,
  "protocol": "ansvk-outreach-sync",
  "batch_id": "3cd9e5ad-b812-4942-b1d3-218f24fd4b1b",
  "project_id": "ansvk_outreach",
  "project_name": "ANSVK Outreach",
  "device_id": "8c8df2a3-8f46-4f1f-98e6-a2c7f8cbb801",
  "device_created_at": "2026-09-12T07:00:00Z",
  "worker_id": "65d24c79-807e-45a4-ae3b-719214ed8d3e",
  "app_version": "0.9.1+16",
  "batch_created_at": "2026-09-12T08:40:00Z",
  "operations": [
    {
      "sequence": 12,
      "operation_id": "264a3b9f-6d55-4b7c-9fa2-c523950317c6",
      "actor_id": "65d24c79-807e-45a4-ae3b-719214ed8d3e",
      "entity_type": "hotspot",
      "entity_id": "22246ce5-b7a2-4bb6-868d-bfc2ca96ac15",
      "revision": 1,
      "action": "create",
      "occurred_at": "2026-09-12T07:15:00Z",
      "payload": {
        "hotspot_id": "22246ce5-b7a2-4bb6-868d-bfc2ca96ac15",
        "owner_id": "65d24c79-807e-45a4-ae3b-719214ed8d3e",
        "name": "Site X",
        "latitude": 16.8409,
        "longitude": 96.1735,
        "location_status": "Available",
        "created_at": "2026-09-12T07:15:00Z",
        "revision": 1,
        "peers": ["Peer 1", "Peer 2"]
      }
    },
    {
      "sequence": 13,
      "operation_id": "55b78ba5-862e-494f-b06e-6983888c55f8",
      "actor_id": "65d24c79-807e-45a4-ae3b-719214ed8d3e",
      "entity_type": "encounter",
      "entity_id": "6eb48071-4787-4939-a122-3cd763b2404b",
      "revision": 1,
      "action": "create",
      "occurred_at": "2026-09-12T07:25:00Z",
      "payload": {
        "encounter_id": "6eb48071-4787-4939-a122-3cd763b2404b",
        "owner_id": "65d24c79-807e-45a4-ae3b-719214ed8d3e",
        "hotspot_id": "22246ce5-b7a2-4bb6-868d-bfc2ca96ac15",
        "client_code": "2026/MY/0004",
        "visit_date": "2026-09-12",
        "client_kind": "New",
        "user_type": "PWID",
        "gender": null,
        "previous_hiv": "Unknown",
        "previous_hcv": "Unknown",
        "previous_hbv": "Unknown",
        "previous_mmt": "No",
        "previous_art": "No",
        "hiv": "Non reactive",
        "hcv": "No",
        "hbv": "No",
        "syphilis": "No",
        "dist_3cc": 2,
        "dist_1cc": 0,
        "dist_lds": 0,
        "dist_alcohol_swab": 2,
        "dist_sterile_water": 2,
        "dist_condom": 0,
        "recollect_3cc": 0,
        "recollect_1cc": 0,
        "recollect_lds": 0,
        "refer_dic": 0,
        "remark": "",
        "created_at": "2026-09-12T07:25:00Z",
        "updated_at": "2026-09-12T07:25:00Z",
        "revision": 1,
        "deleted_at": null
      }
    }
  ]
}
```

### Current APK payload shapes

The dashboard must support these payload shapes from the current APK.

Worker create payload:

```json
{
  "worker_id": "65d24c79-807e-45a4-ae3b-719214ed8d3e",
  "username": "worker1",
  "created_at": "2026-09-12T07:00:00Z"
}
```

Credentials are never included in the audit payload or sync payload.

For a worker create operation, the operation-level `actor_id`, `entity_id`, and payload `worker_id` are the same generated worker ID.

Hotspot create payload:

```json
{
  "hotspot_id": "22246ce5-b7a2-4bb6-868d-bfc2ca96ac15",
  "owner_id": "65d24c79-807e-45a4-ae3b-719214ed8d3e",
  "name": "Site X",
  "latitude": 16.8409,
  "longitude": 96.1735,
  "location_status": "Available",
  "created_at": "2026-09-12T07:15:00Z",
  "revision": 1,
  "peers": ["Peer 1", "Peer 2"]
}
```

If GPS is unavailable, `latitude` and `longitude` are `null`, and `location_status` is `Unavailable`.

Encounter create payload is the encounter row itself. Encounter update and delete payloads are not the row alone; they contain `before` and `after`.

Encounter update payload:

```json
{
  "before": {
    "encounter_id": "6eb48071-4787-4939-a122-3cd763b2404b",
    "owner_id": "65d24c79-807e-45a4-ae3b-719214ed8d3e",
    "hotspot_id": "22246ce5-b7a2-4bb6-868d-bfc2ca96ac15",
    "client_code": "2026/MY/0004",
    "visit_date": "2026-09-12",
    "client_kind": "Old",
    "user_type": null,
    "gender": null,
    "previous_hiv": null,
    "previous_hcv": null,
    "previous_hbv": null,
    "previous_mmt": null,
    "previous_art": null,
    "hiv": "No",
    "hcv": "No",
    "hbv": "No",
    "syphilis": "No",
    "dist_3cc": 0,
    "dist_1cc": 0,
    "dist_lds": 0,
    "dist_alcohol_swab": 0,
    "dist_sterile_water": 0,
    "dist_condom": 0,
    "recollect_3cc": 0,
    "recollect_1cc": 0,
    "recollect_lds": 0,
    "refer_dic": 0,
    "remark": "",
    "created_at": "2026-09-12T07:25:00Z",
    "updated_at": "2026-09-12T07:25:00Z",
    "revision": 1,
    "deleted_at": null
  },
  "after": {
    "encounter_id": "6eb48071-4787-4939-a122-3cd763b2404b",
    "owner_id": "65d24c79-807e-45a4-ae3b-719214ed8d3e",
    "hotspot_id": "22246ce5-b7a2-4bb6-868d-bfc2ca96ac15",
    "client_code": "2026/MY/0004",
    "visit_date": "2026-09-12",
    "client_kind": "Old",
    "user_type": null,
    "gender": null,
    "previous_hiv": null,
    "previous_hcv": null,
    "previous_hbv": null,
    "previous_mmt": null,
    "previous_art": null,
    "hiv": "Reactive",
    "hcv": "No",
    "hbv": "No",
    "syphilis": "No",
    "dist_3cc": 2,
    "dist_1cc": 0,
    "dist_lds": 0,
    "dist_alcohol_swab": 0,
    "dist_sterile_water": 0,
    "dist_condom": 0,
    "recollect_3cc": 0,
    "recollect_1cc": 0,
    "recollect_lds": 0,
    "refer_dic": 1,
    "remark": "Updated after review",
    "created_at": "2026-09-12T07:25:00Z",
    "updated_at": "2026-09-12T07:40:00Z",
    "revision": 2,
    "deleted_at": null
  }
}
```

Encounter delete payload uses the same `{before, after}` shape. In the `after` object, `deleted_at` is set and `revision` is increased.

The dashboard should store both `before` and `after` for audit. Its active encounter view should use the newest accepted `after` state, excluding rows where `deleted_at` is not null.

Example success or partial-success response:

```json
{
  "ok": true,
  "batch_id": "3cd9e5ad-b812-4942-b1d3-218f24fd4b1b",
  "dashboard_received_at": "2026-09-12T08:40:05Z",
  "accepted": [
    {
      "operation_id": "264a3b9f-6d55-4b7c-9fa2-c523950317c6",
      "entity_type": "hotspot",
      "entity_id": "22246ce5-b7a2-4bb6-868d-bfc2ca96ac15",
      "revision": 1
    },
    {
      "operation_id": "55b78ba5-862e-494f-b06e-6983888c55f8",
      "entity_type": "encounter",
      "entity_id": "6eb48071-4787-4939-a122-3cd763b2404b",
      "revision": 1
    }
  ],
  "rejected": []
}
```

Example partial rejection response:

```json
{
  "ok": false,
  "batch_id": "3cd9e5ad-b812-4942-b1d3-218f24fd4b1b",
  "dashboard_received_at": "2026-09-12T08:40:05Z",
  "accepted": [
    {
      "operation_id": "264a3b9f-6d55-4b7c-9fa2-c523950317c6",
      "entity_type": "hotspot",
      "entity_id": "22246ce5-b7a2-4bb6-868d-bfc2ca96ac15",
      "revision": 1
    }
  ],
  "rejected": [
    {
      "operation_id": "55b78ba5-862e-494f-b06e-6983888c55f8",
      "entity_type": "encounter",
      "entity_id": "6eb48071-4787-4939-a122-3cd763b2404b",
      "revision": 1,
      "error_code": "temporary_storage_error",
      "retryable": true,
      "message": "Dashboard could not safely save this encounter yet."
    }
  ]
}
```

The APK may mark only the listed accepted operation IDs and revisions as acknowledged. Rejected or missing operations must stay pending on the phone.

## Operation rules

The dashboard must store every accepted operation durably before acknowledging it.

The dashboard must treat `operation_id` as idempotent:

- If the same operation is received twice, do not create duplicate dashboard records.
- If the same `operation_id` is retried with the same entity, action and revision, return it as accepted if it was already stored.
- If the same `operation_id` appears with conflicting content, reject it with a non-retryable error.

Operations may use these entity types:

- `worker`
- `hotspot`
- `encounter`

Operations may use these actions:

- `create`
- `update`
- `delete`

The dashboard should apply parent records before child records. For example, a hotspot create operation must be accepted before an encounter for that hotspot can be accepted.

For encounter update/delete operations, the operation's top-level `revision` must match `payload.after.revision`.

Every operation must include these wrapper fields:

| Field | Notes |
| --- | --- |
| `sequence` | Local phone audit order |
| `operation_id` | Idempotency key |
| `actor_id` | Worker ID that performed the action |
| `entity_type` | `worker`, `hotspot`, or `encounter` |
| `entity_id` | ID of the affected entity |
| `revision` | Entity revision for this action |
| `action` | `create`, `update`, or `delete` |
| `occurred_at` | UTC timestamp of the action |
| `payload` | Decoded JSON payload from the phone audit row |

## Exact data fields from the APK

App identity fields:

| Field | Notes |
| --- | --- |
| `singleton_id` | Local-only value `1`; does not need to be sent |
| `project_id` | Sent in pairing and sync batch headers |
| `project_name` | Sent in pairing and sync batch headers |
| `device_id` | Sent in pairing and sync batch headers |
| `created_at` | Sent as `device_created_at` in pairing and sync batch headers |

Worker payload fields:

| Field | Notes |
| --- | --- |
| `worker_id` | Generated UUID |
| `username` | Trimmed local username |
| `created_at` | UTC timestamp |

Hotspot payload fields:

| Field | Notes |
| --- | --- |
| `hotspot_id` | Generated UUID |
| `owner_id` | Worker ID |
| `name` | Trimmed hotspot name |
| `latitude` | Number or null |
| `longitude` | Number or null |
| `location_status` | `Available` or `Unavailable` |
| `created_at` | UTC timestamp |
| `revision` | Starts at 1; hotspot editing is not supported yet |
| `peers` | Array of peer-name strings in typed order |

Encounter row fields:

| Field | Notes |
| --- | --- |
| `encounter_id` | Generated UUID |
| `owner_id` | Worker ID |
| `hotspot_id` | Hotspot ID |
| `client_code` | Stored as `YYYY/MY/0000` format from the UI |
| `visit_date` | Local `YYYY-MM-DD`; immutable after creation |
| `client_kind` | `New`, `Old`, or null |
| `user_type` | `PWID`, `PWUD`, `SPOUS`, `MSM`, `FSW`, `FM`, `Youth`, `Other`, or null |
| `gender` | `Male`, `Female`, or null |
| `previous_hiv` | `Unknown`, `Positive`, `Negative`, or null |
| `previous_hcv` | `Unknown`, `Positive`, `Negative`, or null |
| `previous_hbv` | `Unknown`, `Positive`, `Negative`, `Vaccinated`, or null |
| `previous_mmt` | `No`, `Drop Out`, `Current`, or null |
| `previous_art` | `No`, `Defaulter`, `Current`, or null |
| `hiv` | `No`, `Non reactive`, or `Reactive` |
| `hcv` | `No`, `Non reactive`, or `Reactive` |
| `hbv` | `No`, `Non reactive`, or `Reactive` |
| `syphilis` | `No`, `Non reactive`, or `Reactive` |
| `dist_3cc` | Integer >= 0 |
| `dist_1cc` | Integer >= 0 |
| `dist_lds` | Integer >= 0 |
| `dist_alcohol_swab` | Integer >= 0 |
| `dist_sterile_water` | Integer >= 0 |
| `dist_condom` | Integer >= 0 |
| `recollect_3cc` | Integer >= 0 |
| `recollect_1cc` | Integer >= 0 |
| `recollect_lds` | Integer >= 0 |
| `refer_dic` | `0` or `1` |
| `remark` | String, possibly empty |
| `created_at` | UTC timestamp |
| `updated_at` | UTC timestamp |
| `revision` | Starts at 1 and increases on edit/delete |
| `deleted_at` | UTC timestamp or null |

## Dashboard storage expectations

The dashboard should store full history. Do not overwrite old information without keeping the operation history needed for audit.

Minimum dashboard storage concepts:

- Projects.
- Devices.
- Workers.
- Hotspots.
- Hotspot peers.
- Encounters.
- Sync batches.
- Sync operations.
- Operation acknowledgements/rejections.

The dashboard should preserve soft-deleted encounter history. A delete operation means the record should disappear from active views and normal reports, but the dashboard should retain enough history for audit and review.

## Field meanings for dashboard reports

The dashboard should follow the same definitions as the APK:

- `client_code` identifies the same person within a worker's records.
- The same code may appear under different workers.
- The same client code may have records at multiple hotspots on the same day.
- Unique people for a worker/day means distinct active `client_code` values.
- Tests with value `No` mean not tested.
- `Non reactive` and `Reactive` both count as tested.
- Quantities are whole numbers greater than or equal to zero.
- `refer_dic` uses `0` for No and `1` for Yes.
- `deleted_at` marks a soft-deleted encounter.

## Retention and cleanup

The dashboard keeps full history.

The phone may remove old client records only after dashboard acknowledgement. The dashboard response must acknowledge exact `operation_id` and `revision` values. Acknowledging an older revision does not authorize cleanup of a newer local edit.

Hotspot data remains on the phone. Client/encounter data older than the retention window can be cleaned up later only after the phone knows the latest operation was accepted by the dashboard.

## Error code guidance

Use machine-readable error codes so the APK can show clear status and decide whether retry is useful.

Recommended first error codes:

| Error code | Meaning | Retryable |
| --- | --- | --- |
| `not_paired` | Device has not paired with this dashboard | No |
| `invalid_pairing_code` | Pairing code was wrong or expired | No |
| `unsupported_api_version` | Dashboard does not support requested API version | No |
| `unknown_project` | Dashboard does not recognize the project ID | No |
| `invalid_payload` | JSON is missing required fields or has invalid values | No |
| `duplicate_conflict` | Same operation ID was reused with conflicting content | No |
| `missing_parent_hotspot` | Encounter arrived before the required hotspot | Yes |
| `temporary_storage_error` | Dashboard could not safely save data at this time | Yes |

## What the dashboard must not do

- Do not require internet access for local sync.
- Do not require workers to export files manually.
- Do not send other workers' client records back to a phone.
- Do not acknowledge data before it is durably saved.
- Do not treat a received batch as all-or-nothing unless the response clearly lists no accepted operations.
- Do not accept password verifier material in sync batches.
- Do not tell the phone to delete client data unless the exact latest operations have been acknowledged.

## First dashboard screens implied by this contract

The future dashboard should include:

- Dashboard local address and pairing-code screen.
- Paired devices list.
- Worker/account management screen.
- Sync batch log.
- Sync operation detail/rejection review.
- Full-history client encounter review.
- Reporting screens using the definitions in the APK documents.

These screens are dashboard scope, not APK scope.

## Current implementation status

The APK does not yet implement real network sync, a real pairing request or retention cleanup. The APK already stores local operations in an audit/outbox model, has an app identity row with project/device metadata, and has a dashboard connection row reserved for future pairing/address state. The APK can save a dashboard API address and pairing code locally, but this only prepares a later pairing request; it is not pairing and does not permit upload. The APK has a Sync status screen showing pending operation count and "Desktop connection not configured" until the dashboard API exists.
