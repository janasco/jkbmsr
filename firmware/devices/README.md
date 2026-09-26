# Supported devices

Each subdirectory is a compatibility profile for one BMS model or protocol
family. This covers nine vendors, selected at runtime by a device's
`bmsVendor` config field (`"jk"` | `"daly"` | `"jbd"` | `"seplos"` |
`"ant"` | `"tianpower"` | `"basen"` | `"ks"` | `"lolan"`, default `"jk"`) —
see `include/bms/BmsUartClient.h` and `include/bms/BmsBleClient.h` for the
shared interfaces `src/main.cpp` dispatches through. Transport and vendor
selection are independent for JK/Daly/JBD (every one of them has both a
UART and BLE profile); the other six are **BLE only** — no UART parser
exists for them. Profiles identify the protocol and transport used by the
shared firmware; they do not duplicate the parser or Bluetooth
implementation.

Before changing shared BMS code:

1. Check every `profile.json` affected by the protocol or transport change.
2. Run the PlatformIO decoder/parser tests.
3. Add a sanitized device capture under that model's `fixtures/` directory when
   hardware is available.

## Catalog

| Model | Hardware revision | Protocol | Transport | Status |
| --- | --- | --- | --- | --- |
| [JK_B1A8S10P](JK_B1A8S10P/) | 11.XW | JK02_32S | BLE (FFE0/FFE1, auto-discovery) | hardware-tested |
| [JK_B2A24S](JK_B2A24S/) | < 11 | JK02_24S | BLE (FFE0/FFE1, auto-discovery) | protocol-verified |
| [JK_UART_GPS_PORT](JK_UART_GPS_PORT/) | all (software >= 6.0) | 0x4E57_v1 | wired UART-TTL, 115200 baud | synthetic-fixture-only |
| [DALY_UART_0xA5](DALY_UART_0xA5/) | all (0xA5 protocol family) | DALY_0xA5_UART | wired UART-TTL, 9600 baud | synthetic-fixture-only |
| [JBD_UART](JBD_UART/) | all (0xDD/0x77 protocol family) | JBD_UART | wired UART-TTL, 9600 baud | synthetic-fixture-only |
| [DALY_BLE_D2](DALY_BLE_D2/) | all (D2/Modbus BLE protocol family) | DALY_D2_BLE | BLE (FFF0/FFF1/FFF2, auto-discovery) | synthetic-fixture-only |
| [JBD_BLE](JBD_BLE/) | 0xFF00 default service UUID | JBD_UART | BLE (FF00/FF01/FF02, auto-discovery) | synthetic-fixture-only |
| [SEPLOS_BLE](SEPLOS_BLE/) | all (1101-SPxx/ZH/MZ BLE protocol family) | SEPLOS_BLE_1101 | BLE (FF00/FF01/FF02, auto-discovery — shares UUIDs with JBD_BLE) | synthetic-fixture-only |
| [ANT_BLE](ANT_BLE/) | all (2021 BLE protocol family) | ANT_BMS_2021_BLE | BLE (FFE0/FFE1, auto-discovery — shares UUIDs with JK_B* and LOLAN_BLE) | synthetic-fixture-only |
| [TIANPOWER_BLE](TIANPOWER_BLE/) | all (Tianpower BLE protocol family) | TIANPOWER_BLE | BLE (FF00/FF01/FF02, auto-discovery — shares UUIDs with JBD_BLE) | synthetic-fixture-only |
| [BASEN_BLE](BASEN_BLE/) | all (Basen BLE protocol family, incl. VIP/EE/Mabru/Roamer) | BASEN_BLE | BLE (FA00/FA01/FA02, auto-discovery) | synthetic-fixture-only |
| [KS48100_BLE](KS48100_BLE/) | all (KS48100 BLE protocol family) | KS48100_BLE | BLE (FF00/FF01/FF02, auto-discovery — shares UUIDs with JBD_BLE) | synthetic-fixture-only |
| [LOLAN_BLE](LOLAN_BLE/) | all (Lolan BLE protocol family) | LOLAN_BLE | BLE (FFE0/FFE1/FFE2, auto-discovery — shares UUIDs with JK_B* and ANT_BLE) | synthetic-fixture-only |

### Status tiers

- **hardware-tested** — validated end-to-end against our own gateway
  hardware and a real BMS unit.
- **protocol-verified** — decode logic confirmed correct against a real
  device capture (ours or a documented third-party reference), but not yet
  run against our own gateway hardware.
- **synthetic-fixture-only** — only a hand-built fixture matching the
  documented protocol spec exists; no real-device capture has validated it
  yet. Treat as supported on paper, not yet field-proven.

