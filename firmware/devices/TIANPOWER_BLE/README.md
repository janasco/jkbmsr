# Tianpower Smart BMS — BLE protocol

Compatibility profile for Tianpower's BLE protocol: fixed 20-byte response
envelopes (`0x55 0x14 <frameType> ... 0xAA`) with big-endian multi-byte
values and **no checksum** — start/end markers and length are the only
validation.

- Hardware revisions: the whole Tianpower BLE protocol family
- Protocol family: `TIANPOWER_BLE` — 20-byte fixed frames, big-endian
- Connection: BLE, service `0xFF00`, notify characteristic `0xFF01`, write
  characteristic `0xFF02`

**Important**: service `0xFF00` is shared with [`JBD_BLE`](../JBD_BLE/),
[`SEPLOS_BLE`](../SEPLOS_BLE/) and [`KS48100_BLE`](../KS48100_BLE/)
profiles, all of which this firmware also speaks. Address-less auto-discovery
can pick the wrong unit when devices from these families advertise near each
other. Configure an explicit `bmsBleAddress` where this is a concern;
otherwise the advertised `"tianpower"` name hint is preferred, and as a
second line of defense `TianpowerBmsBleClient::loop()` disconnects and
retries against the next-strongest candidate if a connection produces no
valid frame within `kFrameValidationTimeoutMs` (20s).

The implementation is split like every other brand here:
`src/bms/TianpowerBmsDecoder.*` (pure frame decode, hardware-free) and
`src/bms/TianpowerBmsBleClient.*` (NimBLE connection/scan/notify transport).
Ported from `syssi/esphome-tianpower-bms`'s `tianpower_bms_ble.cpp`
(Apache-2.0) — see `docs/third-party-attribution.md`. Decoder coverage is in
`test/test_tianpower_bms_decoder/`.

## Scope of this first pass

The Status frame (`0x83`) is decoded (SOC, pack voltage/current/power and the
three temperatures), as are the two Cell-Voltages chunk frames (`0x88` =
cells 1-8, `0x89` = cells 9-16). The separate Temperatures frame (`0x87`) is
not requested because the status frame already carries all three
temperatures; the balancing-status frame and every write/control command are
not implemented. One request is sent per poll interval (5s) and the three
frames are cycled in rotation; a status frame is always the first thing
requested after a fresh connection, and cell-only samples are not published
until a status frame has been seen (so a partial voltage/SOC-less sample can
never be reported). Read-only.

## Status: synthetic-fixture-only

The only fixture exercising this decoder is hand-built to match the
protocol's documented frame layout, not captured from real hardware. See
`fixtures/README.md` for how to add a real one.

## Hardware regression fixture

After a successful physical-device session, save a sanitized BLE
notification capture in `fixtures/` and add a decoder test against it, then
update this profile's `status`. Never commit Wi-Fi credentials, device
secrets, or cloud tokens.