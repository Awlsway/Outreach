# Outreach Sync v1 Shared Fixtures

**Status:** Accepted by LAN and ANSVK Outreach teams on 2026-09-16  
**Runtime implementation:** Not started

These files define synthetic contract examples shared by the LAN Dashboard and ANSVK Outreach APK.

Rules:

- No value represents a real worker, client, hotspot, device, or credential.
- Both repositories must keep byte-equivalent copies of the approved JSON files.
- Tests may replace server-generated `request_id`, receipt time, and accepted time only when a fixture explicitly marks them variable.
- JSON object key order and whitespace do not define operation identity. LAN parses and canonicalizes operation content before hashing.
- `operation_id`, entity ID, revision, action, and canonical payload together determine whether a repeated operation is identical or conflicting.
- The fake device credential is test-only and must never be accepted outside fixture-mode tests.

Fixture identities:

| Concept | Synthetic value |
| --- | --- |
| Dashboard | `dddddddd-dddd-4ddd-8ddd-dddddddddddd` |
| Device | `11111111-1111-4111-8111-111111111111` |
| Worker | `22222222-2222-4222-8222-222222222222` |
| Hotspot A | `33333333-3333-4333-8333-333333333333` |
| Hotspot missing | `33333333-3333-4333-8333-333333333399` |
| Encounter A | `44444444-4444-4444-8444-444444444444` |

The fixture manifest maps every required contract scenario to an exact file or deterministic test construction.
