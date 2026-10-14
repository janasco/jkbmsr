# JK BMS Contributor

An Android/iOS app for contributing JK-BMS device data to help improve JK-BMS
support across JKBMSR. This repository holds the app skeleton — the shell, theme
and navigation are in place, and the data-contribution features are added on top.

## What this is

- A Flutter app (Dart package `jkbmsr_contributor`) targeting Android and iOS.
- Android namespace / applicationId: `com.jkbmsr.contributor`.
- iOS bundle id: `com.jkbmsr.contributor`.
- Opens to the home screen, from which **"Start a capture"** runs the Phase 3
  capture flow: scan for a JK-BMS, connect, read the device-info and cell-info
  frames, and show a summary of what was captured.

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
│   └── capture_service.dart # Capture orchestration + JK02 reassembly
└── widgets/
    └── brand_mark.dart     # Brand logo with a graceful fallback
test/
├── models/                 # Payload round-trip, versioning, anonymisation
├── screens/                # Capture screen widget tests
├── services/               # Reassembly + capture over a fake radio
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
host bits and advertised name. The consent, review-before-submit and
submit/export flows are later phases and are left as an explicit seam in the
capture screen.


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

## Contributing

Author commits as `janasco <janasco@duck.com>`. Do not add tool attribution or
co-author trailers to commits, pull requests, source, or comments.

Run the checks before opening a pull request:

```bash
flutter analyze && flutter test
```

## License

Distributed under the MIT License. See `LICENSE` for details.
