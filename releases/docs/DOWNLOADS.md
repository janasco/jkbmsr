# Downloads

## Firmware

One release per supported gateway hardware model — see
`firmware/hardware-targets.json` for the current catalog. Each model has
its own directory and its own "latest" pointer:

- `firmware/<target>/latest.json` — current version + artifact paths for
  that target (e.g. `firmware/esp32-classic-4mb/latest.json`)
- `firmware/<target>/v<version>/` — that release's artifacts

Artifacts per release directory:

- `firmware.bin`
- `firmware.sha256`
- `firmware-metadata.json` and OTA signing material (OTA-capable targets
  only — some hardware, like the ESP8266 target, has no OTA subsystem
  and is USB/web-serial reflash only)
- `release.json`
- `RELEASE_NOTES.md`

Bluetooth support is a property of the gateway hardware, not the BMS. A
target needs `capabilities.ble: true` in `firmware/hardware-targets.json`
before it can reach a BMS over Bluetooth. `esp8266-uart-lite` and
`esp32-s2-4mb` have no Bluetooth radio and reach JK-BMS over wired UART
only. The only supported BMS is JK-BMS.

Supporting files:

- `firmware/hardware-targets.json` — the full hardware catalog
- `firmware/releases.json` — the public release-history index used by
  the release host and marketing downloads page, with one `isLatest`
  entry per target hardware model
- `ota/<target>-latest.json` — signed OTA metadata per OTA-capable target
- `ota/keys/public/jkbmsr-ota-p256-20260705.pem`

## Notes

- Source code is not published in this repository
- Private signing material is never published in this repository
- Future Android APK releases will be added under `mobile/android/`
