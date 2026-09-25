# Secure sync transport preparation

Status: implemented with injected-connection tests, 2026-09-17. Not wired to phone UI or the manual runner.

`SecureSyncTransport` supports POST `/api/v1/sync/batches` and GET `/api/v1/sync/status`. It validates HTTPS configuration and the approved SHA-256 pin, reads the hidden device credential from its existing secure store, establishes TLS, then checks the actual peer certificate before sending HTTP headers or payloads. The same TLS socket is supplied to Dart HttpClient; there is no separate certificate-check/request connection. System proxy use is disabled, redirects are refused, and additional connections are refused.

Requests use Bearer authentication. Credentials containing whitespace/control characters are rejected. Batch bodies are sent unchanged as UTF-8 and capped at 1 MiB. Response bodies are capped at 1 MiB and must decode to a JSON object. HttpClient handles normal HTTP framing, including chunked responses. The connect/pin/request operation has a 30-second total deadline; timed-out connections are closed, including a connection completing late. No payloads or credentials are logged.

HTTP error status and JSON are returned for the future caller to interpret; they do not authorize acknowledgement. Status responses never mark outbox operations. Exact device/worker status-response validation and runner integration remain next work. No retries, cleanup or whole-sync success handling is enabled.

Verification: 15 focused transport/orchestration/SQLite tests passed and focused analysis is clean. Six transport tests use injected fake HTTPS connections to verify correct paths/verbs/body, no request after a certificate mismatch, invalid configuration or credential, timeout closure, HTTP credential errors, and oversized upload blocking. These tests do not exercise the concrete TLS/HttpClient adapter, redirects, framing or response-size limit over a real socket. Local TLS integration coverage is required before live phone upload testing.

No version bump, APK build, phone installation, service startup or phone data modification occurred.

## Local HTTPS integration and status validation follow-up

Completed 2026-09-17. All 12 focused HTTPS/status/transport tests passed; focused analysis is clean. Three real TLS tests exercise the concrete SecureSocket/HttpClient adapter with an ephemeral self-signed test certificate and a loopback-only HTTPS server: exact UTF-8 POST and chunked JSON replies, GET status, wrong certificate with zero HTTP requests, redirect refusal, malformed JSON and the response byte limit. Servers close after testing and temporary test keys are deleted. Tests require OpenSSL (the Windows development host uses Git's bundled executable); no office certificate/private key is used.

`SyncStatusResponse` separately validates HTTP/envelope success, exact expected device/worker IDs, active device state, the agreed seven-day policy, request ID, UTC times, nullable paired acknowledgement watermark and warning structure. Status sequence/operation IDs remain informational and cannot mark local operations or authorize cleanup. Three parser tests cover the accepted fixture, first-sync null values, wrong identities/inactive devices and malformed metadata.

The transport/status checks remain disconnected from the runner and phone UI. Next is integrating authenticated status checks and secure uploads into the runner with repository/session/configuration guards and tests. No APK version change/build/install or phone data modification occurred in this follow-up.

References: `13_dashboard_api_contract.md`, `20_phase2_apk_sync_implementation_plan.md`, `26_manual_sync_orchestration.md`, and `docs/fixtures/outreach/v1/sync-status.response.json`.
