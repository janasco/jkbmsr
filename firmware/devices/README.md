# Supported devices

The gateway is **JK-BMS only**. Looking for your exact model number? Skip to
the [JK model matrix](#jk-model-matrix) below — it lists every supported
series. The two profile folders above it are *protocol evidence packs*, not
one-folder-per-model: every JK smart BMS speaks the same JK BLE protocol
family (`FFE0`/`FFE1`, auto-discovery), so one shared implementation serves
them all and a new folder is only added when a model needs distinct handling
or contributes its own hardware-test fixtures. The product speaks the JK BLE protocol
(`FFE0`/`FFE1`, auto-discovery) and nothing else: a stored `bmsVendor` value
from before the product went JK-only falls back to `"jk"` with a serial log
line in `src/main.cpp`, never selecting another protocol.

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

### Status tiers

- **hardware-tested** — validated end-to-end against our own gateway
  hardware and a real BMS unit.
- **protocol-verified** — decode logic confirmed correct against a real
  device capture (ours or a documented third-party reference), but not yet
  run against our own gateway hardware.
- **listed** — same JK protocol family as the profiled models, so expected
  to work with the shared `Jk02Decoder`/`JkBmsBleClient` implementation, but
  not individually hardware-tested. Treat as supported on paper, not yet
  field-proven.

## JK model matrix

Every model below speaks the same JK BLE protocol family as the two profiled
models above and is served by the shared implementation. Only the two
profiles carry individual evidence; everything else in this matrix is
`listed` — never claimed as tested.

### PB Series (`listed`)

JK-PB1A16S10P, JK-PB1A16S15P, JK-PB2A16S10P, JK-PB2A16S15P, JK-PB2A16S20P,
JK-PB2A16S30P.

### B Series

- JK-B1A8S10P — **hardware-tested** (see `JK_B1A8S10P/`)
- JK-B2A24S — **protocol-verified** (see `JK_B2A24S/`)
- Remainder, all `listed`: JK-B1A8S20P, JK-B1A16S15P, JK-B1A20S15P,
  JK-B1A24S15P, JK-B2A8S20P, JK-B2A20S20P, JK-B2A24S15P, JK-B2A24S20P.

### BD Series (`listed`)

JK-BD4A8S4P, JK-BD4A8S6P, JK-BD4A17S4P, JK-BD4A24S4P, JK-BD6A20S6P,
JK-BD6A20S10P, JK-BD6A20S15P, JK-BD6A24S4PD, JK-BD6A24S6P, JK-BD6A24S6PD,
JK-BD6A24S8P, JK-BD6A24S8PD, JK-BD6A24S10P, JK-BD6A24S12P, JK-BD6A24S12PD,
JK-BD6A24S15P, JK-BD6A24S20P, JK-BD6A24S15PD, JK-BD6A20S12P.

### Active Balancer (`listed`)

JK-B4A24S, JK-B2A16S, JK-B15A24S.

### QB Series (`listed`)

JK-QB2A8S20P.
