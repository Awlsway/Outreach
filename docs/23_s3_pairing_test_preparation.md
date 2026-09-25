> Historical development record: manual pairing UI has been removed. Current onboarding is QR-only; see `36_qr_pairing_v1.md` and `37_manual_pairing_cleanup.md`. Retained steps below are not current worker instructions.

# S3 development laptop pairing test preparation

Status: controlled S3 pairing and APK restart user-passed, 17 September 2026. Temporary firewall-rule removal remains pending. No sync upload is enabled.

## Final controlled phone result

Installed APK 0.9.6+21 paired with the final isolated dashboard over Wi-Fi. Owner confirmed certificate match and paired state after APK restart; Ready to sync stays No. Independent dashboard inspection found one active device, one used code, zero accepted operations and zero batches. The test launcher has been stopped; no listener remains on 3001/3443. Old and final protected synthetic state retained. Remove only temporary rule `Outreach-S3-Retry` to close rollback. Restarting the backend against its prior identity/state was not tested or supported by this harness.

## LAN integration review update

Pairing incident update: actual phone walkthrough reached paired state on LAN, then a repeated pairing request using the consumed code returned 409. APK preparation save cleared its earlier paired row. Fix 0.9.6+21 now protects paired settings and repeat attempts and clears the credential on explicit local pairing reset. All 29 focused tests pass, but signed build was declined at the permission gate; phone remains 0.9.5+20, no retry is ready yet. The old live launcher was stopped and its isolated state retained. Retry uses a fresh synthetic store/admin/code after installing the fix, preserving phone records and IDs; it does not test backend restart persistence.

Live setup update: owner authorized proceeding after the operator-page results. Started the isolated launcher with the valid protected S1 certificate reused at the unchanged laptop IP. Runtime is a fresh ACL-protected temporary `ksc-outreach-s3-*` directory, browser administration binds `127.0.0.1:3001/operator`, device API binds `192.168.1.5:3443/api/v1`. The page returned HTTP 200/no-store, selected phone TCP probe passed, actual upload route rejected malformed JSON with HTTP 403 over trusted TLS, and unauthenticated code issuance returned 401 without generating a code. No new firewall rule was needed or created for reachability. Test account creation/code issuance/phone pairing and shutdown remain pending owner interaction. This setup is not successful pairing evidence.

Operator-route alignment: reviewed LAN's sole guard addition, `GET /operator` on the browser surface, and applied it to the Outreach copy. Device routes are unchanged. Both updated copies have SHA-256 `177CCAEAB9976473E27F46D6ECAE640F79BF35F8B5374951E6BA565AB936483E`. Six guard tests pass, including rejection of operator POST/query variants and operator access through the device surface. LAN operator-page integration results remain pending; no live service was started for this alignment.

LAN PM delivered an isolated launcher at `D:\LAN\tools\synthetic_pairing\launcher.ts` and an actual authorization/SQLite integration test. LAN reports that the focused integration test and TypeScript checks passed; the full suite was not rerun. Outreach read the launcher and independently confirmed both request guard copies have SHA-256 `0170AF3080A1135A5951A2DF3AB7E34E1F44F1BFB444EE2EBB97A4ECEEEEC855`.

Review confirms guards are attached before listening, browser binds loopback, synthetic working-directory paths are set before existing route imports, and TLS expiry/SAN/key matching are checked. APK 0.9.5+20 has installed network permission and performs the full fingerprint comparison on the same TLS connection before its pairing POST. The current laptop and phone addresses were rechecked as `192.168.1.5` and `192.168.1.3`.

Usability preparation remains pending: the launcher currently exposes API routes without an operator page. Requested a test-only private loopback page from LAN PM so the owner can perform synthetic setup/login and generate a code through existing authenticated routes, without developer-console commands. Any guard amendment must be reviewed and kept aligned in both repositories. This request does not start a live phone window. Only APK restart persistence is in the first pairing test; launcher restart creates a fresh identity/store and is not a supported persistence test yet.

## Purpose

Test actual APK pairing against the existing LAN dashboard implementation using isolated synthetic dashboard state. The phone must not upload its pending records. Saving APK pairing settings is preparation, not pairing.

## Completed first chunk

Added local test tooling in `tools/synthetic_pairing/request_guard.mjs`. The guard wraps an existing HTTP handler and rejects out-of-scope requests before invoking it. It does not replace dashboard authentication, pairing logic or durable storage.

Device allowlist: `GET /api/v1/health` and `POST /api/v1/pairing/requests`. Upload, sync status, alternate methods, query strings and ambiguous route encodings are rejected with 403. Browser allowlist covers initial synthetic admin setup, login/logout, current user, pairing-code issuance/cancellation, device listing and administration status. MIS/LMIS requests, backups and device revocation are excluded from this first window.

Five local HTTP guard tests passed with `node --test tools/synthetic_pairing/request_guard.test.mjs`. They verify blocked requests never invoke the supplied backend, including malformed upload bodies; allowed requests preserve the supplied backend's rejection response. These tests use instrumented handlers, not the actual LAN authentication or SQLite implementation. Actual integration verification is still required.

No live pairing listener, pairing code, account or dashboard credential was created by this chunk. APK source and phone data were not changed.

## Next small chunk: isolated launcher integration

1. S1 rollback check: subsequent read-only `netsh advfirewall firewall show rule name="Outreach-S1-62f431de"` returned no matching rules, and `netstat` showed no listener on 3443. The old rule must not be silently reused for S3.
2. Prepare a unique protected synthetic working directory under ignored local build storage. The working directory must contain only synthetic users and empty repository/review paths. Configure review/repository paths before importing existing LAN routes; never import them with `D:\LAN` as the process working directory.
3. Use existing dashboard setup/login/session middleware and Outreach browser router. Bind browser administration to laptop loopback on a free test port, such as 3001. Preserve all existing session and role checks.
4. Integrate the device guard before the existing server begins accepting connections. Test its installation against the actual LAN routes on loopback with synthetic storage before allowing the phone access. Do not start the normal office server or bypass authorization to issue codes.
5. Verify unauthenticated code issuance fails, actual upload processing is unreachable, and existing LAN users/data/config remain untouched. Test secrets must not enter repository files or logs.

## Later live phone window

Recheck laptop and phone addresses and certificate SAN/expiry. Choose reuse of the protected S1 synthetic certificate or a fresh certificate explicitly; saving its fingerprint does not provide permanent trust for another certificate. Use fresh synthetic dashboard identity/pepper and preserve them for any server restart check.

Permit selected-phone access to TCP 3443 only through a uniquely named temporary firewall rule. Issue a six-digit code through the authenticated synthetic dashboard session and display it privately to the owner. Pairing creates synthetic worker/device state and consumes the code. Never record the code or device credential in documentation.

Verify matching device/worker identity, paired state after APK restart, and disabled sync. This is not permission to upload records, apply acknowledgements, run retention cleanup or deploy office services. If the phone contains real pending records, confirm their preservation and permit no requests carrying those records. Fully close listeners and remove the temporary rule after the window; retain protected synthetic artifacts until cleanup is approved.

## References

- [Joint sync contract](19_joint_sync_contract_status.md)
- [Dashboard API contract](13_dashboard_api_contract.md)
- [Controlled synthetic connection stages](21_controlled_synthetic_connection_plan.md)
- [S1 runbook](22_s1_certificate_test_runbook.md)
- LAN `docs/Outreach_LAN_API_Technical_Contract_v1.md`
- LAN `server/outreach/browser-router.ts`, `device-server.ts` and `server/middleware/auth.ts`
