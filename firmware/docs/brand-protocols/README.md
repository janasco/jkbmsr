# BMS brand protocol analysis

Deep-scan of the `syssi/*` ESPHome component repos to reuse protocol knowledge in the
jkbmsr firmware. Each per-brand doc is byte-accurate: GATT services/characteristics, exact
request bytes, frame validation, endianness/resolution, and checksums were read from the
component source and cross-checked against test fixtures / captures where available.

Source working copies live under `/tmp/opencode/syssi/` (outside this repo) at the pinned
commit listed in each doc. The firmware implementation must not copy code wholesale — see
`docs/third-party-attribution.md` for licensing notes once code is ported.

## Coverage matrix

| Brand | Transport | Service / chars | Request pattern | Checksum | Endian | Firmware status |
| ----- | --------- | --------------- | --------------- | -------- | ------ | --------------- |
| ANT (2021+) | UART 19200 + BLE | UART `0x7E 0xA1` frames; BLE via same frames (service metadata below) | `7E A1 fn addrLo addrHi len payload ... AA 55` | CRC16-Modbus LE | little | implemented |
| JK | UART + BLE | implemented | — | CRC16-Modbus | little | implemented |
| Daly | UART + BLE | implemented | — | — | little | implemented |
| JBD | UART + BLE | implemented | — | checksum 8-bit XOR | little | implemented |
| Seplos | BLE only | implemented | — | — | little | implemented |
| Tianpower | BLE only | `0xFF00` / notify `0xFF01` / ctrl `0xFF02` | `55 04 <fn> AA` | none | big | **milestone 1** |
| Basen (VIP/EE/Mabru/Roamer) | BLE only | `0xFA00` / notify `0xFA01` / ctrl `0xFA02` | `3A 16 <fn> <len> data <sum lo hi> 0D 0A` | plain 16-bit sum | little | **milestone 1** |
| KS48100 | BLE only | `0xFF00` / notify `0xFF01` / ctrl `0xFF02` | `7B <fn> 00 7D` / write `7B <addr> 02 hi lo 7D` | none | big | **milestone 1** |
| Lolan | BLE only | `0xFFE0` / notify `0xFFE1` / ctrl `0xFFE2` (+ `0xFFF0` alt) | `fnLo fnHi pw pw pw pw` (6B) | custom crc16 on settings | big + float32 | **milestone 1** |
| Offgridtec | BLE only | per-device encryption key | custom | custom | n/a | roadmap |
| Topband (v1) | BLE only passive | `0xFFE0` / notify `0xFFE4` | none (stream `0x5E` SOF) | none | big | roadmap |
| PACE | RS485 Modbus RTU 9600 | no BLE | Modbus 3/6/16 | CRC16-Modbus | big | roadmap |
| virtual-CAN | CAN (masquerade as SMA ext. battery) | no BLE, no client | CAN PDO broadcast | none | little | roadmap |

App parity reference: `jkbmsr-ble/lib/protocols/bms_protocol.dart` +
`lib/services/brand_registry.dart` document the same brands as the mobile app scans them;
the firmware parsers must agree on units and sign conventions (current sign, temperatures).

## Port notes (applies to each milestone-1 doc)

- All five milestone-1 brands are **BLE-only** manufacturers other than our existing
  clients. Every request is a write with no response (`ESP_GATT_WRITE_TYPE_NO_RSP`) to the
  control characteristic; telemetry arrives as notifications on the notify characteristic.
- Poll intervals used upstream: ANT 2 s, Tianpower 2 s, KS 5 s, Lolan 10 s, Basen 5 s
  (queue of 5 commands cycled per update). Match the app's live-update cadence rather than
  upstream defaults where they differ.
- Frame sanity gate before decode: verify start byte (and end byte / trailer where
  declared), enforce `data.size()`, then dispatch on the function/length byte — never
  index past the last data byte.
- Commands requiring a password default to `12345678` (Lolan). Store per-device in the
  BMS profile so the app's passcode screen can override it.
- Parse into the shared telemetry struct (`src/bms`), reuse existing `BmsTelemetry` glue
  and the multi-brand dispatch so one binary auto-detects by BLE service UUID.

## Files

- `ant-bms.md` — full ANT 2021 + legacy spec (from `syssi/esphome-ant-bms`).
- `tianpower-bms.md`
- `basen-bms.md`
- `ks-bms.md`
- `lolan-bms.md`
- `roadmap-brands.md` — Offgridtec, Topband, PACE, virtual-CAN analysis (not milestone 1).