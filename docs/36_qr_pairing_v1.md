# QR Pairing v1

Status: contract and strict APK parser implemented; dashboard rendering, camera scanning and UI are not yet implemented.

## Worker story

After creating an APK account, the worker scans **Add phone** on the office dashboard once. Successful pairing stores the existing hidden device credential. Normal manual sync after that does not require another scan. Re-enrollment requires data-assistant authorization after retirement or revocation; it cannot recover inaccessible unsynced phone data.

## Encoding

The QR text is:

```text
ansvk-outreach://pair/v1#<base64url-without-padding>
```

The decoded bytes are minified UTF-8 JSON with exactly these fields:

```json
{
  "type": "ansvk-outreach-pairing",
  "version": 1,
  "protocol": "ansvk-outreach-sync",
  "protocol_version": 1,
  "project_id": "ansvk_outreach",
  "dashboard_id": "office-dashboard-001",
  "api_base_url": "https://192.168.1.4:3443/api/v1",
  "certificate_sha256": "64-lowercase-hex-characters",
  "pairing_code": "012345",
  "issued_at": "2026-09-23T08:00:00Z",
  "expires_at": "2026-09-23T08:05:00Z"
}
```

The total QR text is at most 2 KiB. Unknown or missing fields are rejected. The API URL must be HTTPS on port3443, path `/api/v1`, with no user information, query or fragment. UTC timestamps use `Z` and zero to six fractional digits. Expiry is after issuance and no more than five minutes later. The phone allows at most one minute of future clock skew and rejects an expired payload.

`dashboard_id` uses the existing dashboard-generated identifier and is checked against the successful pairing response; v1 does not impose a new UUID migration. The certificate is the full SHA-256 fingerprint in lowercase hex. The six-digit code preserves leading zeroes.

## LAN implementation

The authenticated data assistant selects **Add phone**. LAN creates the existing one-use pairing record, builds this complete payload on the server, and renders it locally. No third-party or internet QR service is permitted. The screen shows expiry, a human-readable backup code for the data assistant, cancel/regenerate controls and paired status.

LAN keeps the existing `/api/v1/pairing/requests` endpoint, hashed code storage, atomic single use, five-failure limits, source/device throttles, device credential generation and device lifecycle. No sync-table migration is required. QR delivery may be added to the audit schema later, but it is not required for v1.

## APK implementation

The APK scanner parses this envelope, shows a simple dashboard/address/expiry preview, then uses the existing certificate-pinned `DashboardPairingService`. It never displays the code to the worker and never persists or logs the QR text/code after the attempt. The permanent credential remains in Android secure storage.

An already-paired APK refuses normal rescanning. Planned replacement/reinstall retires the old device; a lost or compromised device is revoked. Password recovery remains suspended. Owner decision: pairing is QR-only, with no manual-entry fallback. The old manual form and worker-triggered clear-pairing controls have been removed; the scanner is still pending implementation.

## Security decision

QR v1 has no separate embedded signature. The authenticated local dashboard is the out-of-band source, the included full certificate fingerprint pins TLS, and the TLS server must possess the matching private key. A signing public key carried inside the same QR would not add trust. A separately provisioned organization trust key would be a future v2 decision.

The QR contains no admin password, device credential, private key or client data. Treat a screenshot as a temporary five-minute credential. Successful use, cancellation, expiry or replacement makes it unusable.

## Delivery phases

1. Contract, fixtures and strict parser.
2. LAN server-built payload and local QR operator UI.
3. APK camera scanner and worker confirmation UI.
4. Cross-project malformed/expiry/cancel/replay/certificate/device-conflict tests.
5. Signed-phone scan, pairing, restart and ordinary manual-sync test.
6. Authorized retirement/revocation and re-enrollment UAT.

The restricted synthetic upload `403` is separate from onboarding. QR pairing must not weaken or work around sync acknowledgement and admission rules.
