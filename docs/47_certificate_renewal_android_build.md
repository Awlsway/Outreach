# Renewal Android Compilation and Package Check

Date: 2026-09-29
Status: Debug Android compilation and APK package inspection passed.
Signed release candidate 0.9.11+26 was subsequently built and verified; see
[signed candidate evidence](48_certificate_renewal_signed_candidate.md).
Real Android runtime/camera/provider checks remain pending.
No APK was installed and no phone was accessed.

## Scope

Verify that the approved certificate validity, initial trust, durable renewal
and normal Sync navigation source compiles for Android and includes the native
bridge/scanner. This is a build checkpoint, not phone UAT or release approval.

The 241 affected source/widget tests recorded in
[subchunk 3](46_certificate_renewal_sync_navigation.md) remain the accepted
source evidence. They were not repeated in this build-only step.

No production code, dependency lock, version source, signing settings or
accepted pairing/sync/renewal contract was changed.

## Build Evidence

Command:

    D:\flutter\bin\flutter.bat build apk --debug --no-pub --dart-define=OUTREACH_SYNTHETIC_SYNC_TEST=false

The assembleDebug task completed successfully in **269.3 seconds**.
Java PeerCertificateMetadata and Kotlin MainActivity were newly compiled.

| Field | Verified value |
| --- | --- |
| Artifact | `D:\outreach\build\app\outputs\flutter-apk\app-debug.apk` |
| Package | `org.ansvk.ansvk_outreach.debug` |
| Label | ANSVK Outreach Test |
| Version/build | 0.9.10 / 25 |
| Size | 195,602,342 bytes |
| SHA-256 | `5E4F058AB813A71B1E98B83458D87B1D54E04621501F6F6D9E96CBFBAC1CBA9F` |
| Android minimum/target | API 24 / 36 |
| Debuggable | true, intentionally for this compilation check |
| Native synthetic export | `BuildConfig.SYNTHETIC_SYNC_TEST = false` in packaged DEX |
| Dart synthetic export | Explicitly false in the build command |
| Signature | APK Signature Scheme v2 verified; Android Debug signer |

This separate debug package cannot update the signed normal package. It is not
the candidate to distribute to workers.

The previous signed release APK was not rebuilt or changed. Its SHA-256 remains
`4C9EE623EE521D9330EB74B3F8163C452DF9A4F4EAC4833BC4C9927741A52172`,
matching the accepted 27 September artifact. That older APK does not include
the renewal changes.

## Packaged Native Inspection

Android SDK apkanalyzer inspected the newly built APK, not just source files:

- Manifest resolves the activity to `org.ansvk.ansvk_outreach.MainActivity`.
- MainActivity DEX calls the superclass Flutter engine configuration, registers
  `org.ansvk.outreach/peer_certificate`, and calls
  `PeerCertificateMetadata.parse(byte[])`.
- Parser DEX contains the X.509 CertificateFactory, exact DER comparison,
  certificate NotBefore/NotAfter reads and type-7 IP SAN extraction.
- Parser failure is connected to the stable `invalid_certificate` bridge
  error, not a permissive certificate fallback.
- GeneratedPluginRegistrant contains MobileScannerPlugin,
  FlutterSecureStoragePlugin and SqfliteSqlCipherPlugin registration.
- MobileScannerPlugin DEX contains its engine/activity attach/detach methods.
- Merged manifest includes CAMERA and INTERNET permissions and
  `allowBackup=false`. Existing location permissions are unchanged.
- Packaged BuildConfig confirms the debug identity and disabled native
  synthetic export. No permanent credential or signing secret was inspected.

Representative inspection commands:

    D:\Dev\Android\Sdk\cmdline-tools\latest\bin\apkanalyzer.bat manifest print build\app\outputs\flutter-apk\app-debug.apk
    D:\Dev\Android\Sdk\cmdline-tools\latest\bin\apkanalyzer.bat dex code --class org.ansvk.ansvk_outreach.MainActivity build\app\outputs\flutter-apk\app-debug.apk
    D:\Dev\Android\Sdk\cmdline-tools\latest\bin\apkanalyzer.bat dex code --class org.ansvk.ansvk_outreach.PeerCertificateMetadata build\app\outputs\flutter-apk\app-debug.apk
    D:\Dev\Android\Sdk\cmdline-tools\latest\bin\apkanalyzer.bat dex code --class io.flutter.plugins.GeneratedPluginRegistrant build\app\outputs\flutter-apk\app-debug.apk
    D:\Dev\Android\Sdk\cmdline-tools\latest\bin\apkanalyzer.bat dex code --class dev.steenbakker.mobile_scanner.MobileScannerPlugin build\app\outputs\flutter-apk\app-debug.apk
    D:\Dev\Android\Sdk\build-tools\36.0.0\apksigner.bat verify --verbose --print-certs build\app\outputs\flutter-apk\app-debug.apk

## What This Does Not Prove

- Actual MethodChannel delivery and Android X.509 provider behavior on a phone.
- Camera permission denial/retry, real QR scanning and camera disposal on
  lock/background on supported phone models.
- Release-mode tree shaking/shrinking, signature compatibility or replacement
  installation preserving existing enrollment and pending records.
- Joint renewal against a running LAN backend and its certificate activation.
- Office installation, Windows service recovery, production certificates,
  network/firewall controls or release acceptance.

The existing duplicate app-version channel registration is unrelated to this
renewal bridge and was left unchanged. No source change was needed to make
this build pass.

## Next Small Step

Signed test candidate 0.9.11+26 is now prepared with the existing normal
application ID/release key and both synthetic export flags disabled.
Its release package and signature are verified in the separate candidate
report. Next request a USB-debug test phone for authorized synthetic LAN/phone
renewal, normal Sync and recovery checks. Do not reset enrollment or pending
records without separate authorization.

No signing key/password was read into chat, no phone was connected or modified,
and no server, service, firewall, office data, USB package, commit or push
was changed.
