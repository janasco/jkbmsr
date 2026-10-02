# JK BMS Local — Bluetooth Monitor & Controller for JK-BMS

[![Flutter](https://img.shields.io/badge/Flutter-3.35.7-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.9.2-0175C2?logo=dart)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-green)](https://github.com/janasco/jkbmsr/tree/main/apps/ble)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/jkbmsr/jkbmsr?include_prereleases)](https://github.com/janasco/jkbmsr/releases)

> **JKBMSR is an independent project.** It is not affiliated with, endorsed by, or sponsored by JK-BMS. "JK-BMS" appears only to describe hardware compatibility.

A modern, high-performance mobile application for real-time Bluetooth Low Energy (BLE) telemetry monitoring and active balancer management for **JK-BMS** battery systems.

Built as an open alternative to proprietary vendor tools, **JK BMS Local** connects directly to hardware via Bluetooth Low Energy without requiring cloud accounts or internet access. There is no simulation/demo mode — every reading on screen comes from a real, connected BMS.

---

## ⚡ Key Features

- **JK-BMS protocol support** — the JK02 protocol was rewritten and verified against the real, community-maintained [`syssi/esphome-jk-bms`](https://github.com/syssi/esphome-jk-bms) reference implementation and cross-checked against a real captured example frame, never guessed from forum posts:
  - Full JK02 protocol: live telemetry (cell voltages, resistance, temps, current, SOC, cycle data) and switch control (charge/discharge/balancer plus extended registers).
  - The Devices scanner shows a "POSSIBLE BMS" tag for hardware it can't name-match but whose Bluetooth service looks like a known BMS protocol, instead of hiding it.

- **Real-Time Battery Telemetry**:
  - State of Charge (SOC %), Total Pack Voltage (V), Live Current (A), and Power (W).
  - Per-cell voltage grid with wire resistance (mΩ) where the brand's protocol reports it, min/max indicators, and delta (mV) highlighting.
  - Thermal monitoring for Power MOSFETs and external battery probes.
  - The Status tab visibly grays out and explains itself (rather than showing stale or fake numbers) whenever nothing is connected, or when the connected brand doesn't report a particular data type yet.

- **BMS Safety Switches with PIN Authorization**:
  - Controls are filtered to only what's actually verified for the connected brand — no switches are shown that this app can't genuinely operate.
  - Protected behind a Security PIN (default `1234`, changeable in the drawer's App settings) that must be entered before any write is sent; the Controls tab shows an honest empty state while no BMS is connected.

- **Per-Field Locked Settings**:
  - Each parameter field has its own small lock/save icon — enter the PIN to unlock just that field, save it to re-lock. Nothing stays unlocked across an app restart.

- **Local, Private Persistence**:
  - Theme choice, last-connected device (for auto-reconnect on launch), and the Security PIN are stored in a local SQLite database on-device — nothing leaves the phone.

- **Bluetooth-Only Permissions**:
  - No location permission requested on Android 12+ (`BLUETOOTH_SCAN` declares `neverForLocation`).

- **Diagnostics Log**:
  - Live in-app log of discovered devices, connection/brand-resolution events, and raw frame activity — useful for confirming what a given piece of hardware is actually advertising.

- **Universal OS Compatibility**:
  - Pure Flutter engine across Android 6.0+ (API 23) through Android 16 (API 36) and iOS.

---

## 📱 Architecture

```
lib/
├── main.dart                   # App entrypoint, theme shell, Bluetooth-off banner, auto-reconnect
├── models/
│   └── bms_models.dart         # BmsStatus, CellInfo, BmsAlarms, BmsCapabilities
├── protocols/
│   └── bms_protocol.dart       # Per-vendor frame builders, parsers, and checksum routines
├── services/
│   ├── ble_service.dart        # BLE scan/connect, per-brand frame reassembly & dispatch, switch writes
│   ├── app_database.dart       # Local SQLite settings store
│   ├── theme_service.dart      # Theme mode, persisted
│   └── security_service.dart   # Control/Settings PIN storage + verification
├── screens/
│   ├── status_screen.dart      # Live telemetry: power flow, cell voltages, wire resistance, diagnostics log
│   ├── controls_screen.dart    # Controls tab: switch toggles + parameter editor on one surface
│   ├── control_screen.dart     # PIN-gated switches, filtered per connected brand
│   ├── bms_parameters_screen.dart # Per-field PIN-gated parameter editors
│   ├── settings_screen.dart    # App settings (drawer): theme picker + control-PIN change
│   └── devices_screen.dart     # BLE scanner — recognized/possible-BMS devices only
└── widgets/                    # Status/Controls tab sections, drawer, modals, PIN dialog
```

See [`docs/ble-protocol-reference.md`](docs/ble-protocol-reference.md) for the
full per-brand protocol specification (GATT UUIDs, frame formats, checksums) and
the reasoning behind brand detection and capability gating.

---

## 🛠️ Building & Running Locally

### Prerequisites
- [Flutter SDK 3.35.7+](https://docs.flutter.dev/get-started/install) (Dart 3.9+)
- Android SDK (API Level 36 target)
- Java 17+

### Commands

1. **Install Dependencies**:
   ```bash
   flutter pub get
   ```

2. **Analyze Code**:
   ```bash
   flutter analyze
   ```

3. **Run Locally**:
   ```bash
   flutter run
   ```

4. **Build Production Release APK**:
   ```bash
   flutter build apk --release
   ```
   *Output: `build/app/outputs/flutter-apk/app-release.apk`*

5. **Build Google Play Store App Bundle (.aab)**:
   ```bash
   flutter build appbundle --release
   ```
   *Output: `build/app/outputs/bundle/release/app-release.aab`*

---

## Enabling real AdMob ads

Ads are **off in any build without `--dart-define`**. Such a build makes no
AdMob SDK call and requests no ad (`lib/services/ads_config.dart`,
`lib/services/ad_sdk.dart`, `lib/widgets/ad_slot.dart`), which is what keeps
`flutter test` and a plain `flutter build` silent.

Ads are **on in the two release builds**. The AdMob ids are not secrets, so
they live in `scripts/ads-defines.sh`, and both `scripts/build-play-aab.sh`
(the Play AAB) and `scripts/publish-release.sh` (the sideload APK) source that
file and pass its `--dart-define` flags. The shipped
`AndroidManifest.xml` carries the real application id; the banner ad unit is
the real one too.

Those are the three settings ads need:

1. **The AdMob application id, in two places.** The native SDK reads it from
   `android/app/src/main/AndroidManifest.xml`
   (`com.google.android.gms.ads.APPLICATION_ID`); the app's gate reads it from
   the `ADMOB_APP_ID` compile-time define. Both must name the same app.
2. **The real banner ad unit id**, passed as `ADMOB_BANNER_AD_UNIT_ID`.
   Omitting it serves Google's test banner — intentional, so a build cannot
   ship a real creative by accident.
3. **`ADS_ENABLED=true`**, the deliberate kill switch.

```bash
flutter build appbundle --release \
  --dart-define=ADMOB_APP_ID=ca-app-pub-…~… \
  --dart-define=ADMOB_BANNER_AD_UNIT_ID=ca-app-pub-…/… \
  --dart-define=ADS_ENABLED=true
```

A sideloaded copy never shows ads regardless, because the entitlement resolves
it as ad-free by product decision (see `remove-ads-lifetime-setup.md`).

Rules that hold whatever is passed:

- **The entitlement wins.** A Supporter (`remove_ads_lifetime`) short-circuits
  before the SDK is initialised or an ad requested; `AdsConfig.mayShowAds` is
  the single ad decision, and `AdSdk.ensureInitialised` re-checks it.
- **The SDK is initialised lazily, at most once per app run**, on the first
  permitted ad — never at import time and never in a test.
- **No ad may render while a BLE connection is being established**, on the
  Connect/Scanning flow, the Control screen, or the PIN dialog. Ads belong on
  the read-only status/history surfaces only.
- **Do not disable a test that asserts inertness.** `test/ad_slot_test.dart`
  and `test/ad_sdk_test.dart` exist to prove a default build stays silent.

---

## 📄 Contributing

Author commits as `janasco <janasco@duck.com>`. Do not add tool attribution or
co-author trailers to commit messages, pull requests, source, or comments.

Two rules matter more than style:

1. **Never guess a protocol.** Any change to a frame format, checksum, register
   address, byte offset, or scaling factor must be verified against a cited
   reference implementation or a frame captured from real hardware. A wrong
   protocol does not fail loudly — it produces a plausible wrong number about a
   battery. See [`docs/ble-protocol-reference.md`](docs/ble-protocol-reference.md).
2. **Never commit secrets.** Signing keys, Firebase config, `.env` files, and
   credentials are excluded by design and supplied locally. See
   [`ABOUT.md`](ABOUT.md).

Run the checks before opening a pull request:

```bash
flutter analyze && flutter test
```

There is no hosted CI in this project; the checks are run locally.

---

## ⚖️ License

Distributed under the MIT License. See `LICENSE` for details.
