# Certificate Renewal v1 Fixtures

This folder is the synthetic cross-project message package for LAN and the Outreach APK.

- `valid-renewal.json` contains one QR renewal envelope, public Ed25519 key, and exact compact-signature digest.
- `device-messages.json` contains bootstrap, claim, receipt, and confirmation examples.
- `invalid-cases.json` names the required rejection cases.
- `manifest.json` lists the JSON fixtures.
- `SHA256SUMS.txt` checks every JSON fixture byte for byte.

All IDs, certificate hashes, messages, and the signed example are synthetic. The one-time signing private key used to make the static example was discarded; no signing key is included here. Never replace these bytes with production phone, certificate, user, or key data.

The same fixture files must be copied byte for byte to the Outreach project. Each project keeps its own test code and runs its parser/crypto against these same messages. Do not run a formatter over JSON fixtures after recording checksums.
