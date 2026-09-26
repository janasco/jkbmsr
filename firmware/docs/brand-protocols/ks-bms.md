# KS48100 BMS / Ks-BMS (BLE)

Analysis of `syssi/esphome-ks-bms` @ `ec157fc`. BLE-only.

## GATT

| Handle | UUID | Role |
| ------ | ---- | ---- |
| service | `0xFF00` | host BMS service |
| notify | `0xFF01` | telemetry notifications |
| control | `0xFF02` (0x10) | write commands |

## Request

Two frame shapes, both write-no-response:

Poll / read: 4 bytes — `[0]=0x7B start   [1]=function   [2]=0x00   [3]=0x7D end`

Register write: 6 bytes — `0x7B <address> 0x02 <hi> <lo> 0x7D`

| Function | Frame | Response length |
| -------- | ----- | --------------- |
| 0x01 | status (device type 1) | 40 B |
| 0x61 | status (device type 2) | same fields |
| 0x02 | cell voltages | |
| 0x03 | temperatures | |
| 0x08 | history | |
| 0x09 | manufacturing date | |
| 0x0A | model name | |
| 0x0B | serial number | |
| 0x0C | model type | |
| 0x04 | basic config (10 regs, len 0x14) | 24 B |
| 0x05 | voltage protection | |
| 0x06 | temperature protection | |
| 0x07 | current protection | |
| 0x64 | status bitmask — **no response** | — |
| 0x74 | Bluetooth SW version | |

## Response

Max 40 bytes. `[0]=0x7B start`, `[1]=function`, `[2]=data_len`, `[3..3+len)=payload`,
last byte `0x7D` end. No checksum. All values **big-endian** 16-bit (`ks_get_16bit`).

Status frame (offsets below are `ks_get_16bit` indices — the absolute byte index of the
big-endian pair in the frame, header bytes 0x7B/type/len included):

| Index | Field | Res |
| ----- | ----- | --- |
| 3 | SoC | ×1 % |
| 5 | Total voltage | ×0.01 V |
| 7 | Avg temperature | ×0.1 °C (int16) |
| 9 | Ambient temperature | ×0.1 °C (int16) |
| 11 | MOSFET temperature | ×0.1 °C (int16) |
| 13 | Current (int16) | ×0.01 A |
| 15 | Capacity remaining | ×0.01 Ah |
| 17 | Full charge capacity | ×0.01 Ah |
| 19 | Nominal capacity | ×0.01 Ah |
| 21 | Cycle capacity | ×0.01 Ah |
| 23 | Charging cycles | ×1 |
| 29 | FET control status | bitmask |
| 31 | Error bitmask | bitmask (report `& 0x0703`) |
| 33 | SoH | ×1 % |

Basic config: 10 × u16 at 16-bit offsets 3,5,…21 (×0.001 V for voltage regs).

## Port notes

- No checksum anywhere — length + start/end bytes only. Guard lengths before indexing.
- Device-type quirk: status request is `0x01` unless `device_type_==2`, then `0x61`.
  Decide via the service pairing / model-name frame (0x0A) or try both on timeout.
- Poll status once per update (upstream 5 s); reading the config frames is write-side →
  defer to settings UI milestone.
- Detect via service `0xFF00` — overlaps nothing else in the roster.