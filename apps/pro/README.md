# jkbmsr-pro

Flutter mobile app for JKBMSR, the JK Battery Management System Remote platform.

## About This Directory

This is the **`apps/pro`** component of a multi-component JKBMSR repository
(firmware, gateway hardware, backend API, web dashboard, docs, release tooling
and this mobile app each live in their own top-level directory).

Some material that exists in the private development repositories is
**deliberately not published here** and must be supplied locally instead:

- **Android release-signing material** — no upload keystore, certificate or
  signing password is in this tree. Create your own upload key, copy
  [`android/key.properties.example`](android/key.properties.example) to
  `android/key.properties` (gitignored) and fill it in. Without it, release
  builds fall back to debug signing with a build-time warning.
- **Firebase project config** — `android/app/google-services.json` and
  `ios/Runner/GoogleService-Info.plist` are not committed. Add your own to
  enable push notifications; the app fails closed (notifications simply
  inactive) without them.
- **Secrets and service credentials** — no `.env` files, API secrets, CI
  secrets or service-account keys are in this tree. Release tooling reads them
  from the environment or from gitignored local files.

The default backend is the production JKBMSR Cloud API. Point the app at your
own deployment by changing the base URL in `lib/services/api_client.dart`.

## Role In The System

`jkbmsr-pro` is the Android/iOS monitoring app.

Responsibilities:

- Customer login.
- Device list.
- Battery dashboard.
- Cell voltage view.
- Alerts view.
- Device settings.
- OTA status display.
- Push notifications for actionable per-device alerts.

## Current Status

- Released. Built and published with `apps/pro/scripts/publish-release.sh`
  (manual — this repository has no CI): a signed APK + AAB are built locally,
  the APK goes to the public download path (`api.jkbmsr.com/mobile/latest.apk`,
  R2-backed) plus a tagged GitHub Release on this repo for history. Current
  version: see `pubspec.yaml`.
- The Android/iOS Flutter client has device claiming (including scanning the
  QR code jkbmsr-web renders on `/onboard`), device list, battery dashboard,
  per-cell voltages (animated battery-shape gauges, not plain progress bars),
  alerts, settings (including device renaming), firmware release history, and
  queued OTA checks implemented in `lib/`.
- The app icon is the real JKBMSR mark (`assets/icon/`), not the default
  Flutter template icon.
- Android-specific Gradle, manifest, and native code live in `android/`.
- iOS-specific Xcode, plist, and native code live in `ios/`.
- The mobile app consumes the same production API used by the web dashboard.
- Signed APK/AAB artifacts are published as GitHub Releases on this repo,
  not committed to the working tree.

## Tech Stack

- Flutter
- Dart
- Android
- iOS
- HTTPS JSON REST API
- JWT authentication
- Firebase Cloud Messaging

## Project Structure

```text
lib/      Shared Flutter application code
android/  Android platform project and configuration
ios/      iOS platform project and configuration
docs/     Product and implementation notes
```

Platform-specific Firebase files belong in their matching platform folder. App
screens and business logic should remain in `lib/` so Android and iOS behave
consistently without duplicated implementations.

## Production API Target

```text
https://api.jkbmsr.com
```

Relevant endpoints already available:

- `POST /v1/user/login`
- `GET /v1/dashboard/devices`
- `GET /v1/dashboard/devices/:deviceId`
- `GET /v1/dashboard/alerts`
- `GET /v1/ota/latest`

## Documentation

- [Mobile roadmap](docs/mobile-roadmap.md)
- [Screen list](docs/screen-list.md)
- [API requirements](docs/api-requirements.md)
- [Notification plan](docs/notification-plan.md)
- [Future Flutter structure](docs/future-flutter-structure.md)
- [Android signing config template](android/key.properties.example)

## Implemented Screens

- Login
- Device list
- Device claim (manual entry or QR scan)
- Battery dashboard
- Cell voltages
- Alerts
- Settings (including device rename)
- OTA status / firmware release history

## Release Readiness Work

- Android push notifications use a real Firebase project. In this public tree
  `google-services.json` is **not** committed (see "About This Directory"); add
  your own to enable push. iOS does not have `GoogleService-Info.plist` yet, so
  iOS push still needs that before it can go through App Store review.
- Android release signing reads `android/key.properties` (gitignored; see
  `android/key.properties.example`) or CI secrets. No keystore and no signing
  password is published in this repository.
- Signed APK/AAB publishing is done and has shipped multiple releases —
  tagged GitHub Releases on this repo for full history, latest APK mirrored
  to R2 for the public download (see above).
- Not yet finished: the Google Play Store listing. Listing assets and copy
  exist; the remaining steps need Play Console access.
- No iOS release pipeline yet (`publish-release.sh` builds/publishes Android only).
