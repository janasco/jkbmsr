# Supported Hardware

JK BMS Remote version 1 supports JK-BMS monitoring only.

## Gateway firmware target

Current production firmware target:

- `esp32dev` (ESP32-family gateway)

## JK-BMS model matrix

Every model below is a JK-BMS product in the same JK protocol family. The
**Status** column is marked honestly — a model is only marked
`hardware-tested` or `protocol-verified` where that evidence actually exists:

- `hardware-tested` — verified against live hardware.
- `protocol-verified` — a protocol capture exists for the model family.
- `listed` — same JK family, not individually tested.

### PB Series

| Model | Status |
|---|---|
| `JK-PB1A16S10P` | `listed` |
| `JK-PB1A16S15P` | `listed` |
| `JK-PB2A16S10P` | `listed` |
| `JK-PB2A16S15P` | `listed` |
| `JK-PB2A16S20P` | `listed` |
| `JK-PB2A16S30P` | `listed` |

### B Series

| Model | Status |
|---|---|
| `JK-B1A8S10P` | `hardware-tested` |
| `JK-B1A8S20P` | `listed` |
| `JK-B1A16S15P` | `listed` |
| `JK-B1A20S15P` | `listed` |
| `JK-B1A24S15P` | `listed` |
| `JK-B2A8S20P` | `listed` |
| `JK-B2A20S20P` | `listed` |
| `JK-B2A24S15P` | `protocol-verified`[^b2a24s] |
| `JK-B2A24S20P` | `protocol-verified`[^b2a24s] |

[^b2a24s]: The capture on file covers the JK-B2A24S family; the two
charge-current variants are not individually captured.

### BD Series

| Model | Status |
|---|---|
| `JK-BD4A8S4P` | `listed` |
| `JK-BD4A8S6P` | `listed` |
| `JK-BD4A17S4P` | `listed` |
| `JK-BD4A24S4P` | `listed` |
| `JK-BD6A20S6P` | `listed` |
| `JK-BD6A20S10P` | `listed` |
| `JK-BD6A20S15P` | `listed` |
| `JK-BD6A20S12P` | `listed` |
| `JK-BD6A24S4PD` | `listed` |
| `JK-BD6A24S6P` | `listed` |
| `JK-BD6A24S6PD` | `listed` |
| `JK-BD6A24S8P` | `listed` |
| `JK-BD6A24S8PD` | `listed` |
| `JK-BD6A24S10P` | `listed` |
| `JK-BD6A24S12P` | `listed` |
| `JK-BD6A24S12PD` | `listed` |
| `JK-BD6A24S15P` | `listed` |
| `JK-BD6A24S15PD` | `listed` |
| `JK-BD6A24S20P` | `listed` |

### Active Balancer

| Model | Status |
|---|---|
| `JK-B4A24S` | `listed` |
| `JK-B2A16S` | `listed` |
| `JK-B15A24S` | `listed` |

### QB Series

| Model | Status |
|---|---|
| `JK-QB2A8S20P` | `listed` |

## Current product focus

- JK-BMS over Bluetooth (BLE)
- ESP32-family gateway
- JKBMSR Cloud backend

## Not supported in version 1

- any BMS other than JK-BMS
- non-ESP32 firmware targets
