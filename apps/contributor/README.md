# JK BMS Contributor

An Android/iOS app for contributing JK-BMS device data to help improve JK-BMS
support across JKBMSR. It is feature-complete for v1: consent, capture, review,
submit and offline export are all implemented.

## What this is

- A Flutter app (Dart package `jkbmsr_contributor`) targeting Android and iOS.
- Android namespace / applicationId: `com.jkbmsr.contributor`.
- iOS bundle id: `com.jkbmsr.contributor`.
- Opens to the home screen, from which **"Start a capture"** runs the capture
  flow: scan for a JK-BMS, connect, read the device-info and cell-info frames,
  and show a summary of what was captured.
- **Review, then contribute**: the review screen shows the exact payload, lets
  you uncheck any field (the serial is off by default), and submits it
  **anonymously** to `POST /v2/contributions` — no account, no token.
  If the submit fails, or on demand, the same bytes can be saved to a `.json`
  file and shared through the OS share sheet, so a capture is never lost.

The app is **read-only**: it never writes to the BMS. It reuses the shared
protocol/model/detection core via the `bms_core` path dependency and adds its
own slim BLE transport (`flutter_blue_plus`) rather than the 60 KB UI-coupled
`ble_service.dart` from `apps/ble`.

## Project layout

```
lib/
├── main.dart               # App entrypoint and theme
├── models/
│   └── contribution.dart   # The versioned donation payload (encode/decode)
├── screens/
│   ├── home_screen.dart    # Home screen + "Start a capture"
│   └── capture_screen.dart # Scan -> connect -> capture -> summary
├── services/
│   ├── app_info.dart       # App name, version, tagline, accent colour
│   ├── ble_transport.dart  # The narrow BLE seam (injectable for tests)
│   ├── flutter_blue_plus_transport.dart  # The real BLE implementation
│   ├── capture_service.dart # Capture orchestration + JK02 reassembly
│   ├── contribution_uploader.dart # Anonymous POST of the payload
│   └── contribution_export.dart   # Offline .json export + share sheet
└── widgets/
    └── brand_mark.dart     # Brand logo with a graceful fallback
test/
├── models/                 # Payload round-trip, versioning, anonymisation
├── screens/                # Capture and review widget tests
├── services/               # Reassembly, capture, upload, export
├── l10n/                   # The submit copy/failure mapping
├── support/                # Captured JK02 fixtures + a fake BLE platform
└── widget_test.dart        # Smoke test: the app launches to the home screen
assets/
├── branding/               # Logo artwork
└── icon/                   # Launcher icon source
```

## Capture payload

A capture produces the versioned JSON donation document defined by the plan
(§4). Its shape and anonymisation defaults are owned by
`lib/models/contribution.dart`: a random `contributionId` (UUIDv7), UTC
timestamps, SI-unit field names, and a redacted-by-default serial number, MAC
host bits and advertised name.

The consent, review-before-submit and submit/export flows are implemented on top
of it. A contributed payload is posted anonymously (no account, no token) by
`lib/services/contribution_uploader.dart`; the identical bytes can be written to
a self-describing file by `lib/services/contribution_export.dart` when the
network is unavailable.


## Prerequisites

- Flutter SDK 3.0 or newer (Dart 3.0+)
- Android SDK (for Android builds) and/or Xcode (for iOS builds)

## Run it

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

## Brand assets

The launcher icons (`android/app/src/main/res/`, `ios/Runner/Assets.xcassets/`)
and the artwork under `assets/` come from the shared JKBMSR brand source. Do not
hand-edit the PNGs; regenerate them from the brand source instead.

The launcher icon set is the family's canonical "cells in an orbit ring" mark,
byte-identical to the generator's `icons/android/ble/` output
(`jkbmsr-private/brand/scripts/brand-asset-gen/generate-remote-mark.js`). There
is currently no `contributor`-specific variant of the mark, so Contributor and
the BLE app share the same launcher artwork; a distinct accent is a brand-repo
design decision, not an app change.

## Version

`pubspec.yaml`'s `version:` is the single source: the Android build reads
`flutter.versionName` / `flutter.versionCode` from it,
`lib/services/app_info.dart` mirrors it by hand for the payload's
`app.version`, and iOS reads it through `FLUTTER_BUILD_NAME` /
`FLUTTER_BUILD_NUMBER`. The family scheme is `MAJOR.MINOR.PATCH+BUILD`, where
`+BUILD` is the Android `versionCode`.

## Releasing

Releases are manual and run by hand; there is no CI.

```bash
scripts/publish-release.sh [version]     # defaults to pubspec.yaml
```

It builds a signed release APK + AAB, verifies the AAB's 16 KB page-size
alignment (a Google Play requirement), records a SHA-256 per artifact, and
creates/updates a `contributor-v<version>` GitHub Release for history. It does
**not** upload to the CDN: unlike `apps/ble` and `apps/pro`, Contributor has no
`api.jkbmsr.com` download endpoint — it ships through Google Play only. The
`.aab` is uploaded to Play Console by hand, along with the Data safety form and
listing assets.

Signing needs `android/key.properties` + the Contributor upload keystore
(gitignored; see `android/key.properties.example`). Without them the release
build falls back to debug signing with a warning and must not be distributed.

## Contributing

Author commits as `janasco <janasco@duck.com>`. Do not add tool attribution or
co-author trailers to commits, pull requests, source, or comments.

Run the checks before opening a pull request:

```bash
flutter analyze && flutter test
```

## License

Distributed under the MIT License. See `LICENSE` for details.
