# Certificate renewal v1 — shared fixture checks

29 September 2026. Test-only chunk on `codex/synthetic-sync-uat-v1`; not committed or pushed.

Copied all six LAN fixture files unchanged into `docs/fixtures/outreach/certificate-renewal-v1/`. SHA-256 comparison against the source confirmed README, manifest, valid renewal, device messages, invalid cases and checksum file match byte-for-byte. A scoped `.gitattributes` rule disables text conversion for this bundle so Git cannot alter checksum bytes. Existing pairing/sync fixtures and their attributes are unchanged.

`test/certificate_renewal_fixture_test.dart` checks the manifest/checksums, published Node Ed25519 signature, original JWS signing bytes, compact grant digest, all device-message field orders/types and cross-message bindings. Disposable in-memory keys demonstrate Dart-to-Node and Node-to-Dart signature verification; no test private key is saved. Node on PATH is required for that test.

`test/renewal_fixture_support.dart` is a test-only reference validator for the flat signed header/payload contract. It checks canonical encoding, duplicate/escaped keys, lexical integers, schema, signature, times and fixture context. It is not imported by application code and is not evidence that the future production parser enforces these rules.

23 of the 29 named matrix cases are exercised with executable mutations. Additional checks cover missing fields, malformed UTF-8 and signature length. These six cases need real credential/server/persistence lifecycle implementation; they are inventoried, not claimed as passed:

- `wrong-device-replay`
- `expired-unused-grant`
- `cancel-claim-race`
- `claimed-receipt-retry`
- `wrong-receipt-replay`
- `cancel-after-claim`

The production parser must rerun the malformed-input corpus later. No Android/native behavior, endpoint permissions, database transitions or recovery race is verified by this chunk.

Validation: `flutter test --no-pub test/certificate_renewal_fixture_test.dart test/qr_pairing_fixture_test.dart` passed 30 checks. The first run exposed a fixed-length-list mistake in the mutation helper; corrected and rerun successfully. Scoped Dart analysis after brace fixes reports no issues. No APK build, signing, installation, application/persistence/UI change, key provisioning or deployment occurred. Earlier uncommitted certificate-validation changes and unrelated `android/Kimi-Test.code-workspace` were preserved.

LAN review finding was based on an earlier source snapshot: its manifest assertion listed two payload files while the next assertion listed three. Re-reading the current LAN test confirms both now list all three; no current discrepancy remains. Outreach did not modify LAN. No signature/digest/device-message contract conflict was found in the supplied fixtures.

References: LAN `docs/37_certificate_renewal_contract_v1.md`; copied fixture README and manifest; Outreach `docs/41_certificate_validation.md`.
