# Firmware 0.1.2

Target hardware: `esp32dev`

Release date: `2026-07-05T07:14:03Z`

## Highlights

- Added signed OTA metadata verification in firmware before update download and apply
- Published OTA metadata with key ID `jkbmsr-ota-p256-20260705`
- Continued `esp32dev` production target support for JK-BMS monitoring

## Verification

- Firmware checksum is published in `firmware.sha256`
- OTA metadata signature is published in `ota/latest.json`
- Public verification key is published at `ota/keys/public/jkbmsr-ota-p256-20260705.pem`

## Notes

- JKBMSR version 1 supports JK-BMS only
- This repository publishes artifacts only and does not contain firmware source code
