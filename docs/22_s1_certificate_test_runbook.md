# S1 certificate-only test runbook

Status: draft runbook, 16 September 2026.

Use this runbook only after the project approves an S1 certificate-only test window. This runbook is for verifying HTTPS certificate trust between one APK and one controlled LAN Outreach test endpoint. It is not permission to enable sync.

## Safety boundary

During S1, do not perform these actions:

- Do not send a pairing request.
- Do not create or consume a pairing code.
- Do not upload a sync batch.
- Do not acknowledge phone operations.
- Do not mark phone records as synced.
- Do not run retention cleanup.
- Do not use real client data for the test.
- Do not expose or record passwords, private keys, device credentials or pairing secrets.

The only APK action under test is **Check certificate** on the Dashboard Pairing screen.

## Approval record

Fill this before the test starts.

| Field | Value |
| --- | --- |
| Approval date/time |  |
| Approved by |  |
| Test operator |  |
| Phone holder |  |
| Windows host name |  |
| Test network name |  |
| Test start time |  |
| Test stop time |  |
| Rollback owner |  |
| Firewall/listener changes allowed? | Yes / No |
| Synthetic-only state confirmed? | Yes / No |

## Host and endpoint record

| Field | Value |
| --- | --- |
| LAN project path | `D:\LAN` |
| LAN build identity or blocker |  |
| Git ownership blocker present? | Yes / No |
| Office API state before test | Disabled / Enabled for test / Unknown |
| Browser dashboard address, if running |  |
| Device API base URL | `https://____:3443/api/v1` |
| Phone-reachable IP or host name |  |
| HTTPS port | `3443` |
| Base path | `/api/v1` |
| Outreach database path for test state |  |
| Outreach backup path for test state |  |
| Rollback/stop command owner |  |

## Certificate record

The approved fingerprint must come from the trusted operator/dashboard display or another trusted local source. Do not treat a fingerprint read from an unverified endpoint as its own proof.

| Field | Value |
| --- | --- |
| Certificate owner/source |  |
| Certificate purpose | Synthetic S1 test / Office test / Other |
| Certificate expiry |  |
| SAN includes phone-reachable address? | Yes / No |
| Full SHA-256 fingerprint handed to phone holder? | Yes / No |
| Trusted channel used for fingerprint | In person / Printed sheet / Other |
| Fingerprint shown on APK only after trusted handover? | Yes / No |

## Phone setup

| Field | Value |
| --- | --- |
| Phone device ID or label |  |
| APK version shown | `0.9.3+18` expected |
| APK release SHA-256 | `413E24677AAAEB4D4EFF50DF29A0755907F28E8DB2D74FEBA5F82451832DD484` expected |
| Signed-in test worker username |  |
| Existing pending records preserved? | Yes / No |
| Real client records avoided? | Yes / No |

## APK steps

1. Open the APK.
2. Sign in with the test worker account.
3. Open **Sync status**.
4. Open **Dashboard pairing**.
5. Enter the approved device API base URL, for example `https://192.168.1.50:3443/api/v1`.
6. Enter any required six-digit placeholder pairing code only if the screen requires saving preparation data. Do not submit a pairing request.
7. Enter the approved full certificate SHA-256 fingerprint.
8. Tap **Check certificate**.
9. Record the result.
10. Repeat once with an intentionally wrong fingerprint and confirm the APK rejects it.
11. Leave the screen without pairing or syncing.

## Expected results

| Case | Expected result | Actual result | Pass? |
| --- | --- | --- | --- |
| Correct HTTPS address + approved fingerprint | Certificate check succeeds |  |  |
| Correct HTTPS address + wrong fingerprint | Certificate check fails with mismatch/untrusted message |  |  |
| Wrong/unreachable address | Certificate check fails without saving paired state |  |  |
| After test, Sync Status **Ready to sync** | Still `No` |  |  |
| After test, paired state | Still not paired |  |  |
| After test, pending changes | Not acknowledged or cleared |  |  |
| After test, retention cleanup | Not run |  |  |

## Evidence to keep

Keep only non-secret evidence:

- Date/time of the test.
- APK version and release hash.
- Windows host name and test endpoint address.
- Certificate expiry, SAN summary and public SHA-256 fingerprint.
- Pass/fail result for correct fingerprint.
- Pass/fail result for wrong fingerprint.
- Confirmation that no pairing, upload, acknowledgement or cleanup happened.
- Rollback confirmation.

Do not keep private keys, passwords, pairing codes, device credential secrets, client payloads or screenshots showing sensitive records.

## Rollback checklist

| Step | Done? | Notes |
| --- | --- | --- |
| Stop synthetic HTTPS listener or restore office API disabled state |  |  |
| Close temporary firewall rule, if one was opened |  |  |
| Confirm browser dashboard/MIS/LMIS behavior unchanged |  |  |
| Confirm no phone records were marked synced |  |  |
| Confirm no retention cleanup ran |  |  |
| Record blockers or follow-up fixes |  |  |

## Result decision

Choose one after the test:

- **S1 passed**: certificate check passed with the approved fingerprint, failed with the wrong fingerprint, and no pairing/sync side effect occurred.
- **S1 blocked**: test could not run safely because host, certificate, firewall, trusted fingerprint handover or data isolation was not acceptable.
- **S1 failed**: the APK did not correctly verify the certificate, or any unauthorized pairing/sync side effect occurred.

If S1 passes, the next development gate is S2 APK live pairing implementation. If S1 is blocked or failed, do not proceed to S2 until the blocker or failure is fixed and reviewed.
