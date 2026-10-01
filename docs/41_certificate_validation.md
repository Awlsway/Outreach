# Shared APK certificate validation — subchunk A

28 September 2026. Local implementation only; no APK build, signing, installation, certificate activation, commit or push. The installed 0.9.10+25 artifact predates these checks.

Follow-up on 29 September: debug Android compilation and packaged
certificate bridge/parser inspection passed. See
[Android build evidence](47_certificate_renewal_android_build.md).
Actual Android provider/MethodChannel runtime, release candidate and phone
verification remain pending. The installed APK is unchanged.

## Scope and unchanged contract

One verifier checks the exact existing full DER SHA-256 pin, UTC NotBefore <= now < NotAfter, and an exact typed IPv4 SAN for the saved HTTPS endpoint. No DNS/CN fallback or IPv6 support is introduced. Server chain trust is not substituted for the approved leaf pin. Pairing, probing and ordinary Sync use the same policy; every fresh retry connection is checked. Sync rechecks dates after its asynchronous context guard immediately before sending.

Verification examines the certificate bytes from the actual TLS socket; no second connection fetches a substitute certificate. The probe closes its socket after obtaining those peer bytes and sends no HTTP request. Pairing and Sync keep the validated socket for sending their original request. TLS may initially accept self-signed certificates for inspection, but application credentials, enrollment codes and payloads are withheld until independent pin/date/IP checks pass. Verification failure is permanent for that attempt, not a transient retry; unconfirmed outbox changes remain pending, no receipt or retention cleanup is manufactured.

Android's standard java.security.cert.CertificateFactory / X509Certificate parser supplies validity epoch times and subjectAlternativeNames type 7 only. Exactly one DER certificate up to 64 KiB is required. Parsing failure or unavailable native bridge blocks sending, including debug mode. No new package dependency was added. A dedicated MethodChannel returns public certificate metadata and does not receive credentials or service data.

QR v1, API/protocol/wire schema, stored pin, pairing configuration, identities, credential, outbox and exact receipt behavior remain unchanged. Certificate renewal, independent signing authority, trust-storage migration, address changes and recovery are not implemented here. Existing fingerprint-mismatch pairing error behavior is retained.

## Focused evidence

Focused verifier/probe/transport/configured service/ordinary UI/QR preservation checks passed; actual loopback TLS and two APK-LAN integration checks passed. Tests cover inclusive start/exclusive expiry, future/expired certificates, full-pin mismatch, typed wrong/missing IP SAN, DNS SAN that looks like an IP, malformed/appended DER, missing parser, validity changing during the context guard, fresh connection validation on retry, no HTTP secrets on failures, preserved credential/identity/pending changes, no acknowledgement or cleanup, and normal byte-preserving pairing/Sync.

Real-TLS tests compile and execute the production Java parser on desktop JDK17 with real OpenSSL-generated DER and loopback TLS. Date rejection uses injected clocks before/after those real certificate dates. Those tests are not Android instrumentation evidence. Unit tests mock only platform metadata to exercise boundary and orchestration policy. Test HTTP mocking and local server listener setup errors were corrected, then affected suites passed. Desktop helper processes and fixtures are temporary and disposed after testing.

No Android native build/linkage, installed-device MethodChannel/provider behavior, physical phone clock/SAN/expiry behavior, or signed artifact is verified by this chunk. A later focused Android validation is required before distribution. No unrelated phone test campaign is requested here.

The unrelated untracked android/Kimi-Test.code-workspace was preserved. Existing duplicate app-version channel registration in MainActivity was left untouched as outside this scope. No live server, certificate, device credential or firewall configuration was changed.

## References

- lib/sync/peer_certificate_verifier.dart
- android/app/src/main/java/org/ansvk/ansvk_outreach/PeerCertificateMetadata.java
- android/app/src/main/kotlin/org/ansvk/ansvk_outreach/MainActivity.kt
- lib/sync/dashboard_certificate_checker.dart, dashboard_pairing_service.dart, secure_sync_transport.dart
- test/peer_certificate_verifier_test.dart, secure_sync_https_integration_test.dart, secure_sync_transport_test.dart, configured_manual_sync_test.dart
- test/jvm_certificate_test_support.dart, peer_certificate_test_support.dart
- docs/40_final_sync_release_checks.md; LAN Outreach_LAN_API_Technical_Contract_v1.md
