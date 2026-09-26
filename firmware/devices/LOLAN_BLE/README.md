# Lolan Smart BMS — BLE protocol

Compatibility profile for Lolan's BLE protocol: 6-byte requests
(`[fnHi fnLo] [password 4 bytes big-endian]`, no checksum), 40-byte
Status/CellInfo responses (108 bytes for Settings), all numeric values
IEEE-754 float32 big-endian, no checksum on status/cell-info.

- Hardware revisions: the whole Lolan BLE protocol family
- Protocol family: `LOLAN_BLE` — fixed 40/108-byte responses, float32
  big-endian
- Connection: BLE, service `0xFFE0`, notify characteristic `0xFFE1`, write
  characteristic `0xFFE2` (an `0xFFF0/0xFFF1/0xFFF2` alias service exists on
  some units but is not listened on)

**Important**: service `0xFFE0` is shared with the [`JK_*`](../JK_B1A8S10P/)
profiles and ANT, both of which this firmware also speaks. Address-less
auto-discovery can pick the wrong unit when devices from these families
advertise near each other. Configure an explicit `bmsBleAddress` where this
is a concern; otherwise the advertised `"lolan"` name hint is preferred, and
as a second line of defense `LolanBmsBleClient::loop()` disconnects and
retries against the next-strongest candidate if a connection produces no
valid frame within `kFrameValidationTimeoutMs` (20s).

The implementation is split like every other brand here:
`src/bms/LolanBmsDecoder.*` (pure frame decode, hardware-free) and
`src/bms/LolanBmsBleClient.*` (NimBLE connection/scan/notify transport).
Ported from `syssi/esphome-lolan-bms`'s `lolan_bms_ble.cpp` (Apache-2.0) —
see `docs/third-party-attribution.md`. Decoder coverage is in
`test/test_lolan_bms_decoder/`.

## Scope of this first pass

The Status frame (request `0xC565`) and the CellInfo frame (request `0x5B65`)
are decoded and cycled one-request-per-poll-interval (5s), status first. The
Settings frame (108 bytes) is never requested, and the turn-on/turn-off
switch commands (which reuse the same request mechanism with distinct
function codes) are not implemented. Read-only.

## Status: synthetic-fixture-only

The only fixtures exercising this decoder are hand-built to match the
protocol's documented frame layout, not captured from real hardware. See
`fixtures/README.md` for how to add a real one.

## Hardware regression fixture

After a successful physical-device session, save a sanitized BLE
notification capture in `fixtures/` and add a decoder test against it, then
update this profile's `status`. Never commit Wi-Fi credentials, device
secrets, or cloud tokens.