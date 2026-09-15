# Release signing plan

Status: preparation complete, 15 September 2026.

This document explains how ANSVK Outreach should move from development debug APKs to a release-signed APK for pilot handover.

## Why this matters

Android uses the app signing key to decide whether one APK can update another installed APK. For pilot phones, the same application ID and signing key must be kept for future updates.

The current development installs used debug APKs. Debug signing is acceptable for development testing only. Pilot distribution should use a release key controlled by the project.

## Current project configuration

The Android app ID is:

`org.ansvk.ansvk_outreach`

The Gradle release build now reads signing settings from a local file:

`android/key.properties`

That file is intentionally ignored by Git. The repository includes only a safe example file:

`android/key.properties.example`

If `android/key.properties` is not present, the release build will not silently use the debug signing key.

## Files that must stay private

Never commit these files to GitHub:

- `android/key.properties`
- the `.jks` or `.keystore` release key file
- any note containing the keystore password, key password or recovery codes

The repository `.gitignore` already excludes `key.properties`, `*.jks` and `*.keystore`.

## Recommended storage

Create the release keystore outside the repository, for example:

`D:\ansvk-private\signing\ansvk-outreach-release.jks`

Keep at least two secure backups controlled by the project owner/data assistant. If the key is lost, installed pilot APKs may not accept future updates signed with a different key.

## Local setup steps

1. Create or choose a secure private folder outside `D:\outreach`.
2. Generate a release keystore into that private folder.
3. Copy `android/key.properties.example` to `android/key.properties`.
4. Replace the example values with the real keystore path, alias and passwords.
5. Build the release APK.
6. Record the version, build number, build date and SHA-256 checksum of the APK in the handover notes.
7. Install the release APK on one test phone first and confirm update behavior before installing on all worker phones.

## Example key.properties shape

```properties
storePassword=YOUR_PRIVATE_STORE_PASSWORD
keyPassword=YOUR_PRIVATE_KEY_PASSWORD
keyAlias=ansvk-outreach
storeFile=D:\\ansvk-private\\signing\\ansvk-outreach-release.jks
```

The real values must stay only on the build computer and in the secure backup location.

## Release build command

After `android/key.properties` exists and points to the private keystore:

```powershell
D:\flutter\bin\flutter.bat build apk --release
```

The expected output is usually:

`build\app\outputs\flutter-apk\app-release.apk`

## Before installing on worker phones

Confirm these items:

- The APK is release-signed with the project release key.
- The application ID remains `org.ansvk.ansvk_outreach`.
- The version/build number is higher than the previous installed APK.
- The phone test script in `17_pre_pilot_readiness.md` passes using dummy data.
- Everyone understands that real dashboard sync is not implemented yet.

## Current status

Release signing structure is prepared. The real keystore was created outside the repository at `D:\private\signing\ansvk-outreach-release.jks`, and the local `android/key.properties` file points to it. Both private files must remain outside GitHub.

Release APK built successfully on 15 September 2026:

- Version: `0.9.2+17`
- Output: `build\app\outputs\flutter-apk\app-release.apk`
- Size: 65,719,214 bytes
- SHA-256: `0F1DDB75304B0B2467C0DE1FC2EDF057DC1F0420C3F5B2D18B853D23176E76AB`

The release APK still needs one-phone release install/update testing with dummy data before worker handover.
