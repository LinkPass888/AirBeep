# Changelog

All notable changes to **AirBeep** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.3.0] - 2026-10-09

### Fixed
- **Xcode 27 build failure.** With `-default-isolation=MainActor`, `@escaping`
  closures can no longer implicitly reference `self`. The silence and restore
  operations now capture `self` explicitly, so the unsigned IPA builds again.
- **iOS 27.0.1 "AirTraffic did not recover"** on read: the airlift read probe
  now targets a non-empty payload and emits more diagnostic logging.

### Added
- Runtime log collection (`AirBeepLog`) with on-device export in the About page
  for easier troubleshooting.
- Manual pairing-file import via `UIDocumentPickerViewController` (`asCopy`),
  avoiding the sandbox security-scope read failure.
- Screen keeps awake and shows a prominent "do not exit the app" warning banner
  while a silence / restore operation is running.

### Security
- Removed the unused `BadQuery` vulnerability; only `airlift` is retained.

### Infrastructure
- Renamed the product from `placard` to `airbeep` across the project, scheme,
  bridging header, workflow, and scripts.
- Updated supported range to iOS/iPadOS 18.0 – 27.2 B2 (aligned with AirCard /
  AirliftSilence).