# Signed Renewal Test APK

Date: 2026-09-29
Status: Signed candidate built and package/signature verified.
No installation, phone access, joint renewal UAT or office deployment performed.
Use only for authorized synthetic testing; do not distribute to field phones.

## Candidate

| Field | Verified value |
| --- | --- |
| Named APK | `D:\outreach\build\renewal-test\ANSVK-Outreach-0.9.11-26-renewal-test.apk` |
| Checksum file | `D:\outreach\build\renewal-test\SHA256SUMS.txt` |
| Version / build | 0.9.11 / 26 |
| Package | `org.ansvk.ansvk_outreach` |
| Label | ANSVK Outreach |
| Size | 84,128,378 bytes |
| APK SHA-256 | `FE1007F8C67FBF52EF78DBCD7C1CE347261F763B56F961626ECC5EE0F265BCA4` |
| Release signer SHA-256 | `d1950cfb4e667e15d3c5877d955cbae812b69dcaf3f8d7a23dda284279639dcb` |
| Signature | One signer; APK Signature Scheme v2 verified |
| Debuggable | false |
| Android automatic backup | false |
| Synthetic export | Native false; Dart explicitly false |

The signer exactly matches the previously accepted signed APK. The application
ID is unchanged and build 26 is greater than its build 25. These are update
prerequisites, not proof that installed-device data survives an update.

The generic Flutter output `build/app/outputs/flutter-apk/app-release.apk`
contains the same verified bytes. Use the named candidate for the next test
handoff so it is not confused with the previous release or debug APK.

## Build

Command, with the native property set only for this process:

    $env:ORG_GRADLE_PROJECT_outreachSyntheticSyncTest='false'
    D:\flutter\bin\flutter.bat build apk --release --no-pub --build-name=0.9.11 --build-number=26 --dart-define=OUTREACH_SYNTHETIC_SYNC_TEST=false

assembleRelease passed in **330.9 seconds** with normal release optimization.
Existing private release signing configuration was reused; no replacement
key was generated and no password/key content was printed or put in a report.
The dependency lock and signing settings were unchanged.

The source version in `pubspec.yaml` is now 0.9.11+26. The installed-version
test covers both 0.9.10+25 and 0.9.11+26: **2 tests passed**.
Scoped analysis of the installed-version reader/test found no issues.
The accepted 241 affected source/widget checks from subchunk 3 were not repeated
for this version-and-packaging-only step.

## Release Package Verification

- apksigner verification passed with one signer, v2 signatures and the exact
  accepted signer certificate fingerprint.
- The packaged XML manifest was parsed and checked for the normal package,
  version/build, non-debuggable state, disabled automatic backup and CAMERA/
  INTERNET permissions.
- Generated release BuildConfig has DEBUG=false and SYNTHETIC_SYNC_TEST=false.
- Packaged optimized activity setup retains the exact peer_certificate,
  app_version and synthetic_review channels and their connected handlers.
- R8 moved/inlined source methods. Inspection followed the actual mapping
  rather than treating a missing original class name as missing functionality:
  activity setup is in `y4.d`; native handlers are in `t0.d`; certificate
  parsing is in `a4.b9` for this artifact only.
- The parser's packaged code contains X.509 DER parsing, exact DER validation,
  NotBefore/NotAfter and typed IP SAN reads. Its handler retains the stable
  invalid_certificate failure and calls that parser.
- The optimized version handler reports exactly 0.9.11+26. The synthetic export
  handler retains the disabled error path.
- GeneratedPluginRegistrant includes optimized scanner (`u4.w`), secure
  storage (`r4.i`) and SQLCipher (`q2.e`) registrations. The scanner's
  actual optimized class is present in the APK.
- The named copy was SHA-256-verified against the inspected signed output.

R8 names are evidence for these bytes only; do not hard-code them into product
logic or use them as identifiers in a future build.

## Previous Release Preserved

The accepted old APK was copied and checked before rebuilding:

`D:\outreach\build\apk-checkpoints\0.9.10-25\ANSVK-Outreach-0.9.10-25-before-renewal.apk`

Its SHA-256 remains
`4C9EE623EE521D9330EB74B3F8163C452DF9A4F4EAC4833BC4C9927741A52172`.

This is artifact preservation, not authorization to downgrade a phone after
its database/trust has advanced. Do not uninstall, clear data or silently
re-enroll a phone to test the new APK.

## Provenance and Changes

Built from the existing dirty development workspace on
`codex/synthetic-sync-uat-v1`, based on commit
`fed2b46cf8e42b8dd5c251033d29252a60d259ff`.
The APK includes the uncommitted approved validity/trust/renewal/navigation
changes; the base commit alone cannot reproduce this candidate.

This step changes only the source version, its focused version test and
progress/evidence documents. Existing unrelated changes were preserved.
Generated APKs, checksums and preserved binaries stay under ignored build
directories. No branch change, commit, push, server restart or deployment.

## Remaining Test Gate

With separate authorization, connect a USB-debug synthetic test phone:

1. Record the installed signed package/version, device/worker enrollment and
   pending-data baseline before any update.
2. Install this candidate as an update without uninstalling or clearing data.
3. Verify actual Android certificate-provider/MethodChannel behavior, camera
   permission and renewal QR scanning inside the real lock/session shell.
4. Use an isolated LAN test setup for initial trust, renewal claim/confirmation,
   ordinary Sync and supported failure/retry recovery. Keep office production
   certificates and data unchanged.
5. Check exact acknowledgements, retained credential/identity/pending records,
   no duplicate service operations and clear failure messages.

Package inspection cannot replace these runtime tests. Joint renewal, office
activation/service/network/backup checks and PM release acceptance remain
pending. No accepted pairing, credential, QR or sync batch contract changed.
