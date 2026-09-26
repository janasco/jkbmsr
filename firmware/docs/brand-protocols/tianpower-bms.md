# Tianpower BMS (BLE)

Analysis of `syssi/esphome-tianpower-bms` @ `f412bf1`. BLE-only; no UART variant.

## GATT

| Handle | UUID | Role |
| ------ | ---- | ---- |
| service | `0xFF00` | host BMS service |
| notify | `0xFF01` (0x13) | telemetry notifications |
| notify2 | `0xFF03` (0x18) | unused by upstream |
| control | `0xFF02` (0x15) | write commands |

## Request

4-byte frame, write-no-response:

```
[0]=0x55 start   [1]=0x04 request   [2]=function   [3]=0xAA end
```

No checksum. One frame per command; the poll queue is sent back-to-back each update:

| Function | Frame | Response data[2] |
| -------- | ----- | ---------------- |
| 0x83 | status | 0x83 |
| 0x84 | general info | 0x84 |
| 0x85 | mosfet status | 0x85 |
| 0x87 | temperatures | 0x87 |
| 0x88 | cell voltages 1-8 | 0x88 |
| 0x89 | cell voltages 9-16 | 0x89 |
| (0x8A | cell 17-24 — commented out upstream) | |
| 0x81 / 0x82 | software / hardware version (one-shot on connect) | |

## Response

Exactly **20 bytes**: `[0]=0x55`, `[19]=0xAA`, `[1]=0x14` (constant "response" tag),
`[2]=<requested function>`. Dispatch on `data[2]`. All multi-byte values **big-endian**
(`(d[i]<<8)|d[i+1]`). Aliases confirm the mask: uncertainty is zero for 16S/32S (max 16 != 32).

Known status layout (`data[2]=0x83`):

| Index | Len | Field | Res |
| ----- | --- | ----- | --- |
| 3 | 2 | SoC | ×1 (signed? treat u16) |
| 5 | 2 | Total voltage | ×0.01 V |
| 7 | 2 | Avg temperature | ×0.1 °C (int16) |
| 9 | 2 | Ambient temperature | ×0.1 °C (int16) |
| 11 | 2 | MOSFET temperature | ×0.1 °C (int16) |
| 13 | 2 | Current (int16 signed) | ×0.01 A |
| 15 | 2 | Unknown | |
| 17 | 2 | SoH | ×1 % |
| 19 | 1 | `0xAA` end | |

General info / temperatures / cell frames: 16-bit BE fields starting at index 3; cell
voltages at `(i*2)+3` ×0.001 V. Float32 not used (u16 scalars only).

## Port notes

- Detection: scan for service `0xFF00` where the device advertises Tianpower — upstream
  additionally reads SW/HW version frames for the model text sensor; not needed for
  telemetry auth gate.
- Response is fixed-size; the streaming parser must buffer notifications until `data.size()==20`.
- Poll all 6 queue frames per cycle for cell coverage; the app shows 16 cells max → frames
  0x88 + 0x89 suffice (0x8A only for 24-cell packs).