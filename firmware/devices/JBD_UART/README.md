# JBD-BMS — UART protocol

Compatibility profile for JBD (Jiabaida) BMS units over their wired UART-TTL
transport — the same protocol family sold rebranded as Xiaoxiang, Overkill
Solar, LLT Power, and others. 25+ specific commercial models have been
community-reported compatible with this protocol family (see
`syssi/esphome-jbd-bms`'s own supported-devices list).

- Hardware revisions: the whole `0xDD`/`0x77` UART protocol family
- Protocol family: `JBD_UART` — variable-length request/response frames,
  16-bit checksum (two's-complement byte-sum negation)
- Connection: wired UART-TTL, **9600 baud** (not JK's 115200)

The implementation is in `src/bms/JbdBmsParser.*`, ported from
`syssi/esphome-jbd-bms`'s `components/jbd_bms/jbd_bms.cpp` (Apache-2.0) — see
`docs/third-party-attribution.md`. Decoder coverage is in
`test/test_jbd_bms_parser/`.

## Scope of this first pass

Two commands are implemented: hardware info (`0x03` — pack
voltage/current/SOC/capacity/cycles/protection status/balancing/temperature)
and cell info (`0x04` — the full individual per-cell voltage array, unlike
Daly's classic protocol this arrives in one frame rather than several).
JBD also supports a write command set (enable/disable charge and discharge
MOSFETs, force a SOC reset, etc.) and a BLE transport — neither is
implemented in this pass; this profile is read-only, UART-only.

## Status: synthetic-fixture-only

The only fixtures exercising this decoder are hand-built to match the
protocol's documented frame layout, not captured from real hardware. See
`fixtures/README.md` for how to add a real one.

## Hardware regression fixture

After a successful physical-device session, enable `bmsUartCaptureEnabled`
to log real frames (`JKBMSR_JBD_UART_FRAME` lines) over serial, save the
sanitized bytes in `fixtures/`, and add a decoder test against them, then
update this profile's `status`. Never commit Wi-Fi credentials, device
secrets, or cloud tokens.
