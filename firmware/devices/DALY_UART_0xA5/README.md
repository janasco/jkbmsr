# Daly Smart BMS — 0xA5 UART protocol

Compatibility profile for Daly's classic consumer "Smart BMS" line (J/T/A/U/W/ND
series). This is a **different, incompatible protocol** from the newer Daly
H/K/M/S-series (which uses a `0xD2`-framed, quasi-Modbus protocol) — this
profile covers only the `0xA5` family.

- Hardware revisions: the whole `0xA5` protocol family (no single hardware
  version gates it, unlike JK's software-version threshold)
- Protocol family: `DALY_0xA5_UART` — fixed 13-byte request/response frames,
  additive checksum
- Connection: wired UART-TTL, **9600 baud** (not JK's 115200 — this is a real
  difference, not an oversight; set `bmsUartBaudRate` accordingly when
  switching a gateway to this vendor)

The implementation is in `src/bms/DalyBmsParser.*`, ported from the protocol
described in `maland16/daly-bms-uart` (MIT) — see
`docs/third-party-attribution.md`. Decoder coverage is in
`test/test_daly_bms_parser/`.

## Scope of this first pass

Only five of Daly's nine documented commands are implemented: pack
voltage/current/SOC (`0x90`), min/max cell voltage (`0x91`), temperature
(`0x92`), MOSFET/charge status (`0x93`), and cell/temp-sensor count plus
cycles (`0x94`). Deliberately **not** implemented yet: the individual
per-cell voltage array (`0x95`, a multi-frame response), per-sensor
temperatures (`0x96`), cell balance state (`0x97`), and failure codes
(`0x98`). `BatteryTelemetry.cellCount` is left at 0 rather than reporting a
count with no matching per-cell voltages.

## Status: synthetic-fixture-only

The only fixtures exercising this decoder are hand-built to match the
protocol's documented frame layout, not captured from real hardware. See
`fixtures/README.md` for how to add a real one.

## Hardware regression fixture

After a successful physical-device session, enable `bmsUartCaptureEnabled`
to log real frames (`JKBMSR_DALY_UART_FRAME` lines) over serial, save the
sanitized bytes in `fixtures/`, and add a decoder test against them, then
update this profile's `status`. Never commit Wi-Fi credentials, device
secrets, or cloud tokens.
