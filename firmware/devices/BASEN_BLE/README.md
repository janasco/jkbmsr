# Basen BMS — BLE protocol (incl. VIP / EE / Mabru / Roamer rebrands)

Compatibility profile for Basen's BLE protocol: length-prefixed envelopes
(`0x3A`/`0x3B`, addr `0x16`, function, length, payload, `0x0D 0x0A` trailer)
with a **plain 16-bit sum** checksum (not a CRC) stored little-endian, and
all telemetry values little-endian — the odd-one-out among the milestone-1
brands, which is why the checksum is kept explicit in the decoder.

- Hardware revisions: the whole Basen BLE protocol family (also sold under
  VIP / EE / Mabru / Roamer branding — same protocol)
- Protocol family: `BASEN_BLE` — length-prefixed, plain-sum checksum,
  little-endian
- Connection: BLE, service `0xFA00`, notify characteristic `0xFA01`, write
  characteristic `0xFA02`

Unlike the rest of the milestone-1 set, service `0xFA00` is **not** shared
with the other supported brands, so address-less auto-discovery is
less error-prone here — an advertised `"basen"` name hint is preferred
anyway, and `BasenBmsBleClient::loop()` still disconnects and retries
against the next-strongest candidate if a connection produces no valid frame
within `kFrameValidationTimeoutMs` (20s).

The implementation is split like every other brand here:
`src/bms/BasenBmsDecoder.*` (pure frame decode, hardware-free) and
`src/bms/BasenBmsBleClient.*` (NimBLE connection/scan/notify transport).
Ported from `syssi/esphome-basen-bms`'s `basen_bms_ble.cpp` (Apache-2.0) —
see `docs/third-party-attribution.md`. Decoder coverage is in
`test/test_basen_bms_decoder/`.

## Scope of this first pass

The Status frame (`0x2A`), General Info frame (`0x2B`) and the two
Cell-Voltages chunk frames (`0x24` = cells 1-12, `0x25` = cells 13-24) are
decoded and cycled one-request-per-poll-interval (5s), status first. Settings
frames and every write/control command are not implemented. Read-only.

## Status: synthetic-fixture-only

The only fixtures exercising this decoder are hand-built to match the
protocol's documented frame layout, not captured from real hardware. See
`fixtures/README.md` for how to add a real one.

## Hardware regression fixture

After a successful physical-device session, save a sanitized BLE
notification capture in `fixtures/` and add a decoder test against it, then
update this profile's `status`. Never commit Wi-Fi credentials, device
secrets, or cloud tokens.