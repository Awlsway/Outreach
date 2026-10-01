# Outreach APK current state

Updated: 2026-10-01. Owner: Outreach APK PM. See [verification and release status](APK_VERIFICATION_AND_RELEASE_STATUS.md) before calling a feature or build accepted. The renewal source checkpoint is based on `fed2b46cf8e42b8dd5c251033d29252a60d259ff` on `codex/synthetic-sync-uat-v1`; check `git log -1` for its resulting commit.

## Purpose and worker flow

English-only Flutter/Dart Android app for four workers, each with their own phone. A worker self-registers locally with username/password. Authentication and a four-minute inactivity lock protect the app; backgrounding conceals it. Workers create/search their own hotspots, then enter, view, edit and delete only their own encounters. Hotspot creation records typed peer names and GPS when available; an explicit unavailable location is allowed. Hotspot editing is deferred. All work can be recorded offline.

Client code is manually entered in `YYYY/MY/0000` style and identifies a person within one worker's records; codes may overlap between workers. Visits are for today only. The same worker/client/hotspot/day cannot have two active encounters, but a client may visit different hotspots that day. New means first visit in the calendar year, chosen by the worker; an old client does not automatically reload details. HIV/HCV/HBV/syphilis tests, distribution, recollection, referral and optional new-client details follow [the field plan](01_plan.md) and [schema](../lib/database/schema.dart). Today's clients served counts distinct client codes across that worker's active encounters, not visits.

## Android source and storage

| Component | Current responsibility |
| --- | --- |
| `lib/app.dart`, `lib/auth/` | App/session shell, worker self-registration, password sign-in/unlock and inactivity/foreground protection |
| `lib/hotspots/`, `lib/database/outreach_repository.dart` | Worker-scoped hotspot, encounter, today's records and summary workflows |
| `lib/database/app_database.dart`, `schema.dart`, `retention_cleanup.dart` | App-private SQLCipher SQLite, schema **9**, migrations, audit/outbox, confirmation and seven-day cleanup |
| `lib/database/database_key_store.dart`, `lib/sync/device_credential_store.dart` | Android secure storage for local database key and permanent device credential; neither is a sync payload |
| `lib/sync/qr_pairing_*`, `dashboard_pairing_service.dart` | QR-only initial phone enrollment; no worker manual address/code/fingerprint form |
| `lib/sync/initial_certificate_trust.dart`, `certificate_renewal_*`, `peer_certificate_verifier.dart`, `lifecycle_gate.dart` | Authenticated initial trust, certificate date/pin/IP-SAN checks, signed renewal and retained recovery state |
| `lib/sync/configured_manual_sync.dart`, `manual_sync_runner.dart`, `secure_sync_transport.dart`, `sync_*` | Worker-tapped foreground Sync, bounded retries/Stop, exact acknowledgement and retention gating |

Audit operations and the outbox retain stable operation IDs and revisions for idempotent upload. The phone sends only the signed-in worker's changes to the paired office HTTPS device API; it does not download coworkers' records. The dashboard keeps full history. After a successful destination-bound acknowledgement, local client/encounter information older than seven days is eligible for cleanup; unconfirmed changes are held, and hotspots remain. `last_successful_sync_at` is distinct from pending count.

Package `org.ansvk.ansvk_outreach`; current source version `0.9.11+26` in `pubspec.yaml`. Sync payload schema is **6** (`lib/sync/sync_protocol.dart`); protocol/API is v1. These are independent of local SQLite schema 9 and LAN migration 8. The signed candidate is named `build/renewal-test/ANSVK-Outreach-0.9.11-26-renewal-test.apk`; exact checksum and provenance are in the status document. The candidate was built before this source checkpoint from its dirty working tree. The older base commit alone does not reproduce it; a byte-for-byte rebuild from the new checkpoint has not been performed.

## Connection and trust decisions

The worker scans an assistant-generated, one-use dashboard QR for initial enrollment. That QR supplies the configured phone API address, full certificate fingerprint, pairing code and expiry; code lifetime is at most five minutes. The APK has no worker manual-entry fallback. Successful enrollment stores a permanent device credential separately from the worker password. Browser login and phone credential are separate. Ordinary Sync is manual by button over the same LAN and uses HTTPS port 3443 with the saved approved identity and certificate trust.

Initial certificate trust is saved and confirmed before ordinary Sync. Renewal requires an approved signed QR and online claim/confirmation; retained receipts determine the effective successor pin/generation. Pending claim or confirmation blocks ordinary Sync and survives restart. Renewal preserves worker/device identity, credential, endpoint and pending records. It does not automatically migrate the endpoint, replace a missing/expired renewal authority or bypass an unreachable successor. Re-enrollment after retired/revoked/lost app state uses a new device identity and data-assistant authorization; it cannot recover inaccessible unsynced data. Password recovery remains suspended for the pilot; workers need a device passcode.

The office production address is a deployment choice, **not an APK hard-coded IP**. LAN currently records reserved `192.168.1.50`, phone API `https://192.168.1.50:3443/api/v1` and browser HTTPS 3444 for office preparation. The home test endpoint `192.168.1.5:3443` belonged to a now-removed isolated backend and is not an office setting. See LAN [current state](../../LAN/docs/LAN_CURRENT_STATE.md) in the separate checkout for its authoritative choices.

The dashboard's agreed Outreach view is Summary and Records. Outreach client codes do not link to MIS CCode or modify clinical/logistics KPIs. Map/Mapping integration is outside the agreed APK scope.
