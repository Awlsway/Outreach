# ANSVK Outreach

Offline Android app for four outreach workers. Local SQLite storage, offline
registration/login, logout, the one-minute lock, hotspot search/creation with
GPS fallback, and offline client entry are implemented. Desktop sync, encounter
editing/deletion, and summaries are next.

## Structure

- `docs/`: requirements, implementation plan, decisions and development specification.
- `lib/`: Dart application entry point and app shell.
- `android/`: native Android build configuration.
- `test/`: automated checks.

Database implementation details are in [the database guide](docs/06_local_database.md).
Account behavior and testing are in [accounts and lock](docs/07_accounts_and_lock.md).
Hotspot behavior and the phone walkthrough are in [hotspots](docs/08_hotspots.md).
Client-entry behavior is in [client entry](docs/09_client_entry.md).

Start with [the development specification](docs/04_development_specification.md)
and [project status](docs/03_decisions_and_tracking.md).

## Development

Created with Flutter 3.44.1 and Dart 3.12.1.

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

This scaffold is not ready for real client information.
