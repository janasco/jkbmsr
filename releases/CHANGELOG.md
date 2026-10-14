# Changelog

All notable public release artifacts for `jkbmsr-releases` are recorded here.

## 2026-07-05

### Added

- Initial public release repository structure
- Firmware `esp32dev` release `v0.1.2`
- Public checksum verification guide
- OTA security overview
- Public OTA verification key for `jkbmsr-ota-p256-20260705`

## 2026-07-27

### Added

- Mobile `jkbmsr-mobile` `v1.0.0` (built 2026-07-27, APK + AAB with checksums)
- Mobile `jkbmsr-mobile` `v1.1.0` (built 2026-07-27, APK + AAB with checksums)

## 2026-07-31

### Added

- Mobile `jkbmsr-mobile` `v1.2.1` (built 2026-07-31, APK with checksum)
- Mobile `jkbmsr-mobile` `v1.2.2` (built 2026-07-31): app logo, app name, Google Sign-in support

## 2026-08-01

### Added

- Mobile `jkbmsr-mobile` `v1.2.7` (built 2026-08-01): native Google sign-in on Android instead of a browser tab
- Mobile `jkbmsr-mobile` `v1.2.8` (built 2026-08-01, APK + AAB with checksums)
- Mobile `jkbmsr-mobile` `v1.2.9` (built 2026-08-01, APK + AAB with checksums)
- Mobile `jkbmsr-mobile` `v1.2.10` (built 2026-08-01, APK + AAB with checksums)

### Mobile v1.2.x highlights (build dates not recorded in artifacts)

- Mobile `jkbmsr-mobile` `v1.2.3`: battery cell animations, simplified bottom nav, relocated OTA settings, improved alerts tab
- Mobile `jkbmsr-mobile` `v1.2.4`: cell charging/discharging animations, gateway settings reorganization, alerts severity filtering with live search and inline acknowledge, automatic entitlement binding, gateway sharing cap of 5 users

## 2026-09-29

### Added

- Mobile `JKBMSR BLE` `v4.17.20+40` (GitHub release, built 2026-09-29)
- Mobile `JKBMSR Pro` `v1.3.30` (GitHub release, built 2026-09-29)

## 2026-09-30

### Added

- Mobile `JKBMSR Pro` `v1.3.31`: release tags now carry the marketing version, not the versionCode

## 2026-10-01

### Added

- Mobile `JKBMSR BLE` `v4.17.22+42` (GitHub release, built 2026-10-01)
- Mobile `JK BMS Local` (renamed) `v4.17.23+43`
- Mobile `JK BMS Remote` (renamed) `v1.3.32`
- Mobile `JK BMS Remote` `v1.3.33`: push notifications enabled

## 2026-10-02

### Added

- Mobile `JK BMS Remote` `v1.3.34`: in-app Cloud Service checkout link removed
- Mobile `JK BMS Remote` `v1.3.35`: moved to the new Firebase project
- Mobile `JK BMS Bluetooth` (renamed) `v4.17.24+44`

## 2026-10-03

### Added

- Mobile `JK BMS Remote` `v1.3.36`: Alerts summary spacing fix
- Mobile `JK BMS Remote` `v1.3.37`: Play installs update through Play, APK kept for sideloads

## 2026-10-08

### Added

- Mobile `JK BMS Bluetooth` `v4.17.25+45` (GitHub release, built 2026-10-08)
- Mobile `JK BMS Remote` `v1.3.38`: 16 KB memory page-size support (Play requirement)
- Mobile `JK BMS Remote` `v1.3.39`: notification permission asked at sign-in, alert channel created
- Mobile `JK BMS Remote` `v1.3.40`: dedicated Protection Warnings toggle (cell imbalance / over-current)
- Mobile `JK BMS Bluetooth` `v4.17.26+46` and `JK BMS Remote` `v1.3.41`: loading skeletons; Remote also gains an offline-alert countdown

## 2026-10-09

### Added

- Mobile `JK BMS Bluetooth` `v4.17.27+47`: logbook drawer
- Mobile `JK BMS Remote` `v1.3.42`: remote Wi-Fi setup and update check
- Mobile `JK BMS Remote` `v1.3.43`: in-app acknowledge/mute for offline alerts
- Mobile `JK BMS Remote` `v1.3.44`: API path `/v1`
- Firmware `v0.9.2`: release script isolates the pioarduino (C6) core dir and bootstraps pip

## 2026-10-13

### Added

- Firmware `v0.9.3`: BLE-only BMS link
- Firmware `v0.9.4`: N16R8 Octal-PSRAM target
- Firmware `v0.9.5`: N16R8 on arduino-esp32 3.2.0 / IDF 5.4.1
- Firmware `v0.9.6` (GitHub release)
- Firmware `v0.9.7` (GitHub release, current per `releases/ota/*-latest.json`)

No tagged firmware releases exist between `v0.1.2` and `v0.9.2` in this
repository. Mobile `v1.2.0`, `v1.2.5`, and `v1.2.6` have no notes files and no
releases here, so they are not listed.
