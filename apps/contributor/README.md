# JK BMS Contributor

An Android/iOS app for contributing JK-BMS device data to help improve JK-BMS
support across JKBMSR. This repository holds the app skeleton — the shell, theme
and navigation are in place, and the data-contribution features are added on top.

## What this is

- A Flutter app (Dart package `jkbmsr_contributor`) targeting Android and iOS.
- Android namespace / applicationId: `com.jkbmsr.contributor`.
- iOS bundle id: `com.jkbmsr.contributor`.
- Opens to a placeholder home screen titled **"JK BMS Contributor"**.

There is no BLE or networking yet. The app is intentionally a clean shell so
product flows can be built and reviewed on their own.

## Project layout

```
lib/
├── main.dart               # App entrypoint and theme
├── screens/
│   └── home_screen.dart    # Placeholder home screen
├── services/
│   └── app_info.dart       # App name, tagline and accent colour
└── widgets/
    └── brand_mark.dart     # Brand logo with a graceful fallback
test/
└── widget_test.dart        # Smoke test: the app launches to the home screen
assets/
├── branding/               # Logo artwork
└── icon/                   # Launcher icon source
```

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
