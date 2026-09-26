# Lolan BMS (BLE)

Analysis of `syssi/esphome-lolan-bms` @ `76a34ae`. BLE-only.

## GATT

| Handle | UUID | Role |
| ------ | ---- | ---- |
| service | `0xFFE0` (alt `0xFFF0`) | host BMS service |
| notify | `0xFFE1` (alt `0xFFF1`, handles 0x10/0x11) | telemetry notifications |
| control | `0xFFE2` (alt `0xFFF2`, handle 0x13) | write commands |

Alt service pair used by some device firmwares; register both.

## Request

6 bytes, write-no-response:

```
[0]=fnHi   [1]=fnLo   [2]=pw>>24   [3]=pw>>16   [4]=pw>>8   [5]=pw>>0
```

32-bit password embedded **big-endian**; default `12345678` (`0x00BC614E`).

| Command | fn (u16 BE) | Response |
| ------- | ----------- | -------- |
| status | `0xC565` | frame 0x01, 40 B |
| cell info | `0x5B65` | frame 0x02, 40 B |
| settings | `0x5600` | frame 0x03, 108 B |

## Response

`[0]=frame type` (0x01/0x02/0x03). Multi-byte ints **big-endian**; several fields are
**IEEE-754 float32**. Settings frame ends with trailer `5A A5`. Custom `crc16_lolan`
(table-based, init 16, post-transforms) used for settings integrity — status/cell frames
are validated by length + trailer only.

Status frame (40 B):

| Offset | Len | Field | Type |
| ------ | --- | ----- | ---- |
| 0 | 1 | frame type 0x01 | u8 |
| 1 | 1 | 0x00 | u8 |
| 2 | 1 | switch bitmask (bit1 discharging, bit2 charging) | u8 |
| 3 | 1 | status / error bitmask | u8 |
| 4 | 4 | total voltage | f32 V |
| 8 | 4 | negative current | f32 A |
| 12 | 4 | positive current | f32 A |
| 16 | 4 | temperature 1 | f32 °C |
| 20 | 4 | temperature 2 | f32 °C |
| 24 | 4 | total discharged capacity | f32 Ah |
| 28 | 4 | total charged capacity | f32 Ah |
| 32 | 4 | runtime | u32 s |
| 36 | 2 | charging cycles | u16 |
| 38 | 2 | SoC | u16 % |

Current: use the larger magnitude of the two float32s; sign flips the negative one.
Power = V × I; split charging/discharging.

Cell frame (0x02): 16 cells, each 2 B BE ×0.001 V from an offset, plus balancing info —
parse into shared cell array.

## Port notes

- Password gate: wrong password → confirmations (`0x35`/`0x21`/`0x2F`) instead of data.
  Surface "pairing/password" error to the app and read the passcode from the BMS profile.
- Detection: service `0xFFE0`/`0xFFF0` with notify/control pair.
- Float32 helper `ieee_float_(u32)` reinterprets big-endian bits — port verbatim semantics.
- Only the status frame is needed for live telemetry; settings is the write-side UI
  (defer), so `crc16_lolan` only matters for that later milestone.