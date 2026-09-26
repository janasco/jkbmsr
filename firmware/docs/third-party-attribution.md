# Third-Party Attribution

## syssi/esphome-jk-bms (Apache License 2.0)

The JK-BMS protocol implementations in this firmware are ported from
[syssi/esphome-jk-bms](https://github.com/syssi/esphome-jk-bms), licensed
under the Apache License, Version 2.0
(https://www.apache.org/licenses/LICENSE-2.0):

- `src/bms/JkBmsParser.{h,cpp}` — UART-TTL (0x4E57) request/response framing,
  additive checksum, and the positional register map of the
  "read all registers" (0x06) response.
- `src/bms/Jk02Decoder.{h,cpp}` — BLE JK02 frame format (0x55AA EB90), 8-bit
  checksum, the 24S/32S cell-info layouts, and the device-info layout.
- `test/test_jk02_decoder` — the 24S fixture is a device capture documented in
  the upstream source comments.

Changes from upstream: reimplemented as transport classes independent of
ESPHome (no Component/sensor framework), telemetry mapped to this project's
`BatteryTelemetry` struct, automatic 24S/32S layout detection from the
device-info hardware version, and NimBLE-based transport instead of
esp32_ble_tracker.

## maland16/daly-bms-uart (MIT License)

`src/bms/DalyBmsParser.{h,cpp}` implements Daly's classic 0xA5-framed
consumer "Smart BMS" UART protocol (J/T/A/U/W/ND series — NOT the newer
0xD2/Modbus H/K/M/S-series, an incompatible protocol), ported from the frame
layout and command set documented by
[maland16/daly-bms-uart](https://github.com/maland16/daly-bms-uart), licensed
under the MIT License, which itself sources the protocol from Daly's own
published "UART/485 Communications Protocol V1.2" document.

Changes from upstream: reimplemented as a `BmsUartClient` (see
`include/bms/BmsUartClient.h`) independent of the Arduino library's own
class shape, telemetry mapped directly to `BatteryTelemetry`. Only 5 of the
9 documented commands are implemented in this first pass — see
`devices/DALY_UART_0xA5/README.md` for exactly which, and what's deliberately
left for a follow-up.

## syssi/esphome-daly-bms (Apache License 2.0)

`src/bms/DalyD2Decoder.{h,cpp}` and `src/bms/DalyBmsBleClient.{h,cpp}`
implement Daly's H/K/M/S-series BLE protocol (frame start `0xD2`,
Modbus-style function/register reads, CRC16-Modbus checksum) — a
**different, incompatible protocol from `DalyBmsParser`'s UART protocol
above**, despite being the same brand. Ported from
[syssi/esphome-daly-bms](https://github.com/syssi/esphome-daly-bms)'s
`components/daly_bms_ble/daly_bms_ble.cpp` (`decode_status_data_()`),
licensed under the Apache License, Version 2.0.

Changes from upstream: reimplemented as a `BmsBleClient` (see
`include/bms/BmsBleClient.h`)/pure-decoder split mirroring
`JkBmsBleClient`/`Jk02Decoder`, CRC16-Modbus reimplemented directly (not
available as a library here). Only the "status" register range (address
`0x0000`) is implemented — settings, version, balancer-switch commands, and
the separate "P81" protocol variant (frame start `0x81`/`0x51`) are not —
see `devices/DALY_BLE_D2/README.md`.

## syssi/esphome-jbd-bms (Apache License 2.0)

`src/bms/JbdBmsParser.{h,cpp}` implements JBD (Jiabaida)'s protocol
(0xDD...0x77 framing), ported from
[syssi/esphome-jbd-bms](https://github.com/syssi/esphome-jbd-bms)'s
`components/jbd_bms/jbd_bms.cpp`, licensed under the Apache License,
Version 2.0. The frame format is byte-identical between UART and BLE
(confirmed against upstream's separate `components/jbd_bms_ble` component),
so `src/bms/JbdBmsBleClient.{h,cpp}` (BLE transport, service `0xFF00`/notify
`0xFF01`/control `0xFF02`, ported from `jbd_bms_ble.cpp`'s UUID defaults)
reuses this same decoder rather than a second one.

Changes from upstream: reimplemented as `BmsUartClient`/`BmsBleClient`
implementations, telemetry mapped directly to `BatteryTelemetry`. Not
implemented: JBD's write/control command set, and the password-
authentication sub-protocol (`0xFF 0xAA`...`0x77` framed) a minority of BLE
units require — see `devices/JBD_BLE/README.md`.

## syssi/esphome-seplos-bms (Apache License 2.0)

`src/bms/SeplosBleDecoder.{h,cpp}` (pure frame decode) and
`src/bms/SeplosBmsBleClient.{h,cpp}` (NimBLE transport, service `0xFF00`,
notify `0xFF01`, control `0xFF02`) implement Seplos's 1101-SPxx/ZH/MZ BLE
protocol (`0x7E`...`0x0D` framing, CRC-16/XMODEM checksum), ported from
[syssi/esphome-seplos-bms](https://github.com/syssi/esphome-seplos-bms)'s
`components/seplos_bms_ble/seplos_bms_ble.{cpp,h}`, licensed under the
Apache License, Version 2.0.

Changes from upstream: reimplemented as a `BmsBleClient` implementation,
telemetry mapped directly to `BatteryTelemetry`. Only the "single machine
data" command (`0x61`) is implemented — manufacturer-info, settings,
parallel-data, and all write/control commands are not. The separate,
much-less-proven V3/EMU10xx protocol variant (`seplos_bms_v3_ble` upstream)
is not implemented at all — see `devices/SEPLOS_BLE/README.md`. No Seplos
UART support exists in this firmware.

## syssi/esphome-ant-bms (Apache License 2.0)

`src/bms/AntBmsDecoder.{h,cpp}` (pure frame decode) and
`src/bms/AntBmsBleClient.{h,cpp}` (NimBLE transport, service `0xFFE0`,
characteristic `0xFFE1` for both writes and notifications) implement ANT's
2021-style BLE protocol (`0x7E 0xA1 ... 0xAA 0x55` framing, CRC-16/MODBUS
checksum), ported from
[syssi/esphome-ant-bms](https://github.com/syssi/esphome-ant-bms) at commit
`87d89bd` — `components/ant_bms_ble/ant_bms_ble.cpp`, licensed under the
Apache License, Version 2.0.

Changes from upstream: reimplemented as a `BmsBleClient` implementation,
telemetry mapped directly to `BatteryTelemetry`. Only the 2021 status
response (function `0x11`) is decoded — the device-info/settings commands,
all write/control commands, and the older 2019-style protocol are not; see
`devices/ANT_BLE/README.md` and `docs/brand-protocols/ant-bms.md`.

## syssi/esphome-tianpower-bms (Apache License 2.0)

`src/bms/TianpowerBmsDecoder.{h,cpp}` (pure frame decode) and
`src/bms/TianpowerBmsBleClient.{h,cpp}` (NimBLE transport, service `0xFF00`,
notify `0xFF01`, control `0xFF02`) implement Tianpower's BLE protocol
(fixed 20-byte `0x55 0x14 <type> ... 0xAA` frames, big-endian, no checksum),
ported from
[syssi/esphome-tianpower-bms](https://github.com/syssi/esphome-tianpower-bms)
at commit `f412bf1` — `components/tianpower_bms_ble/tianpower_bms_ble.cpp`,
licensed under the Apache License, Version 2.0.

Changes from upstream: reimplemented as a `BmsBleClient` implementation,
telemetry mapped directly to `BatteryTelemetry`. Status (`0x83`) and the two
cell-voltage chunks (`0x88`/`0x89`) are decoded; the separate temperatures
frame (`0x87`), balancing frame, and all write/control commands are not; see
`devices/TIANPOWER_BLE/README.md` and
`docs/brand-protocols/tianpower-bms.md`.

## syssi/esphome-basen-bms (Apache License 2.0)

`src/bms/BasenBmsDecoder.{h,cpp}` (pure frame decode) and
`src/bms/BasenBmsBleClient.{h,cpp}` (NimBLE transport, service `0xFA00`,
notify `0xFA01`, control `0xFA02`) implement the Basen BLE protocol
(`0x3A`/`0x3B`...`0x0D 0x0A` framing with the distinctive **plain 16-bit
sum** checksum, little-endian telemetry), ported from
[syssi/esphome-basen-bms](https://github.com/syssi/esphome-basen-bms) at
commit `9dde442` — `components/basen_bms_ble/basen_bms_ble.cpp`, licensed
under the Apache License, Version 2.0. Basen batteries are also sold under
VIP / EE / Mabru / Roamer branding, sharing this same protocol.

Changes from upstream: reimplemented as a `BmsBleClient` implementation,
telemetry mapped directly to `BatteryTelemetry`. Status (`0x2A`), general
info (`0x2B`) and the two cell-voltage chunks (`0x24`/`0x25`) are decoded;
settings frames and all write/control commands are not; see
`devices/BASEN_BLE/README.md` and `docs/brand-protocols/basen-bms.md`.

## syssi/esphome-ks-bms (Apache License 2.0)

`src/bms/KsBmsDecoder.{h,cpp}` (pure frame decode) and
`src/bms/KsBmsBleClient.{h,cpp}` (NimBLE transport, service `0xFF00`, notify
`0xFF01`, control `0xFF02`) implement the KS48100 BLE protocol
(`0x7B <type> <len> ... 0x7D` framing, big-endian, no checksum), ported from
[syssi/esphome-ks-bms](https://github.com/syssi/esphome-ks-bms) at commit
`ec157fc` — `components/ks_bms_ble/ks_bms_ble.cpp`, licensed under the
Apache License, Version 2.0.

Changes from upstream: reimplemented as a `BmsBleClient` implementation,
telemetry mapped directly to `BatteryTelemetry`. Status (`0x01`, plus the
layout-identical `0x61` device-type-2 variant) and cell voltages (`0x02`)
are decoded; config/settings frames and all register writes are not; see
`devices/KS48100_BLE/README.md` and `docs/brand-protocols/ks-bms.md`.

## syssi/esphome-lolan-bms (Apache License 2.0)

`src/bms/LolanBmsDecoder.{h,cpp}` (pure frame decode) and
`src/bms/LolanBmsBleClient.{h,cpp}` (NimBLE transport, service `0xFFE0`,
notify `0xFFE1`, control `0xFFE2`) implement the Lolan BLE protocol
(6-byte requests with a 4-byte big-endian password, fixed 40/108-byte
responses, all numerics IEEE-754 float32 big-endian), ported from
[syssi/esphome-lolan-bms](https://github.com/syssi/esphome-lolan-bms) at
commit `76a34ae` — `components/lolan_bms_ble/lolan_bms_ble.cpp`, licensed
under the Apache License, Version 2.0.

Changes from upstream: reimplemented as a `BmsBleClient` implementation,
telemetry mapped directly to `BatteryTelemetry`. Status (`0xC565` request)
and cell info (`0x5B65` request) are decoded; the checksummed Settings frame
(`0x03`) and the switch turn-on/turn-off commands are not; see
`devices/LOLAN_BLE/README.md` and `docs/brand-protocols/lolan-bms.md`.
