# Downloads

## Firmware

Firmware is installed from the **logged-in browser flasher** at
<https://web.jkbmsr.com/flash>. An account is required; the flasher fetches the
release from the authenticated JK BMS Remote API (`api.jkbmsr.com/v1/flash/*`),
which streams it from private firmware storage.

This host (`cdn.jkbmsr.com`) does **not** serve firmware binaries. It is not a
manual-download mirror any more.

## Public verification material

- `ota/<target>-latest.json` — signed OTA metadata per OTA-capable target
- `ota/keys/public/<key id>.pem` — the OTA public verification key
- `docs/VERIFY_FIRMWARE.md` — how to verify the signature and checksum

Bluetooth support is a property of the gateway hardware, not the BMS. A target
needs `capabilities.ble: true` before it can reach a BMS over Bluetooth.
`esp8266-uart-lite` and `esp32-s2-4mb` have no Bluetooth radio and reach JK-BMS
over wired UART only. The only supported BMS is JK-BMS.

## Notes

- Source code is not published in this repository.
- Private signing material is never published in this repository.
- Android APK/AAB release artifacts ship as GitHub Release assets; only their
  checksums and notes are published under `mobile/android/`.
