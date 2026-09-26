# Basen BMS (BLE) — also VIP / EE / Mabru / Roamer

Analysis of `syssi/esphome-basen-bms` @ `9dde442`. BLE-only rebrand; the protocol is shared
by the Basen/VIP/EE/Mabru/Roamer hardware family.

## GATT

| Handle | UUID | Role |
| ------ | ---- | ---- |
| service | `0xFA00` | host BMS service |
| notify | `0xFA01` (0x12) | telemetry notifications |
| control | `0xFA02` (0x15) | write commands |

## Frame

Request/response share an envelope. Telemetry payload (status + cell voltages, incl.
register numbers in writes) is **little-endian**; the checksum is a **plain 16-bit sum**
of bytes `[1 .. 3+data_len]` (addr+func+len+payload), stored little-endian — verified
against `BasenBmsBle::chksum_` in the repo header (a simple accumulator, not a CRC).

Request (via `build_frame_`), write to control char:

```
[0]=start 0x3A | 0x3B   [1]=address 0x16   [2]=function   [3]=data_len
[4 .. 4+len)=data
[4+len]=crc lo   [5+len]=crc hi   0x0D 0x0A
```

`chksum_` is a plain 16-bit accumulator over bytes

`[1 .. 3+data_len]`

(start byte excluded). Stored little-endian. Two start bytes select the command set:
- `0x3A` — queued poll commands (below)
- `0x3B` — immediate status request on connect

## Commands

| Function | Frame | Notes |
| -------- | ----- | ----- |
| 0x2A | status | main telemetry (~32 B frame: mosfet bits, SoC, pack V/I, temps) |
| 0x2B | general info | |
| 0x24 | cell voltages 1-12 | |
| 0x25 | cell voltages 13-24 | 16S packs stop here |
| 0x26 | cell voltages 25-34 | only for 32S-class |
| 0x27 | protect IC | |
| 0xE8 | settings | |
| 0xEA | settings alternative | |
| 0xFE | balancing | balancing bitmask |
| 0xEB | write | register write (data=value byte) |

Poll: connect sends status with `0x3B`, then each update cycles the queue — status, general
info, cell 1-12, cell 13-24, balancing — starting a new cycle only after the previous
response arrives (throttle `0s` until cycle finishes).

## Response

Buffered from multiple notifications; terminates on `0x0D 0x0A`. Validate
`data[0] ∈ {0x3A, 0x3B}`, recompute `chksum_` over bytes `[1 .. 3+data[3]]`, compare with
the stored CRC (`[frame_len-4]<<0 | [frame_len-3]<<8`), then dispatch on `data[2]`.

## Port notes

- Frame assembly must tolerate MTU-split notifications across multiple GATT values; the
  parser is trailer-driven (`0x0D 0x0A`), not size-driven.
- Multi-byte reads on this link are **little-endian** (status: current/voltage/capacity
  u32, temps int8; cells u16 — unlike every other milestone-1 brand).
- Cell count is implicit from which chunk frames arrive (`0x24` → cells 1-12,
  `0x25` → 13-24, `0x26` → 25-34) — good candidate for the shared "cell count detection"
  path; each chunk carries `data[3] = 2*12` cells in the 1-12 frame.
- No password on the wire.