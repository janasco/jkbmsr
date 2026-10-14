# Third-Party Attribution

## syssi/esphome-jk-bms (Apache License 2.0)

The JK-BMS protocol implementations in this firmware are ported from
[syssi/esphome-jk-bms](https://github.com/syssi/esphome-jk-bms), licensed
under the Apache License, Version 2.0
(https://www.apache.org/licenses/LICENSE-2.0):

- `src/bms/Jk02Decoder.{h,cpp}` — BLE JK02 frame format (0x55AA EB90), 8-bit
  checksum, the 24S/32S cell-info layouts, and the device-info layout.
- `test/test_jk02_decoder` — the 24S fixture is a device capture documented in
  the upstream source comments.

Changes from upstream: reimplemented as transport classes independent of
ESPHome (no Component/sensor framework), telemetry mapped to this project's
`BatteryTelemetry` struct, automatic 24S/32S layout detection from the
device-info hardware version, and NimBLE-based transport instead of
esp32_ble_tracker.
