# KS48100 Smart BMS — BLE protocol

Compatibility profile for KS's 48100 BMS: envelopes (`0x7B <frameType> <len>
<payload> 0x7D`) with **no checksum** at all — validated by exact length and
start/end markers only — and big-endian multi-byte values.

- Hardware revisions: the whole KS48100 BLE protocol family
- Protocol family: `KS48100_BLE` — length-bounded frames, big-endian,
  no checksum
- Connection: BLE, service `0xFF00`, notify characteristic `0xFF01`, write
  characteristic `0xFF02`

**Important**: service `0xFF00` is shared with [`JBD_BLE`](../JBD_BLE/),
[`SEPLOS_BLE`](../SEPLOS_BLE/) and [`TIANPOWER_BLE`](../TIANPOWER_BLE/)
profiles, all of which this firmware also speaks. Address-less auto-discovery
can pick the wrong unit when devices from these families advertise near each
other. Configure an explicit `bmsBleAddress` where this is a concern;
otherwise the advertised `"ks"`/`"ks48100"` name hint is preferred, and as a
second line of defense `KsBmsBleClient::loop()` disconnects and retries
against the next-strongest candidate if a connection produces no valid frame
within `kFrameValidationTimeoutMs` (20s).

The implementation is split like every other brand here:
`src/bms/KsBmsDecoder.*` (pure frame decode, hardware-free) and
`src/bms/KsBmsBleClient.*` (NimBLE connection/scan/notify transport). Ported
from `syssi/esphome-ks-bms`'s `ks_bms_ble.cpp` (Apache-2.0) — see
`docs/third-party-attribution.md`. Decoder coverage is in
`test/test_ks_bms_decoder/`.

## Scope of this first pass

The Status frame (`0x01`; the layout-identical `0x61` variant for device
type 2 is accepted too) and the Cell Voltages frame (`0x02`) are decoded and
cycled one-request-per-poll-interval (5s), status first. State of health is
read from the trailing bytes when present (`length > 34`); config/settings
frames and all register writes are not implemented. Read-only.

## Status: synthetic-fixture-only

The only fixtures exercising this decoder are hand-built to match the
protocol's documented frame layout, not captured from real hardware. See
`fixtures/README.md` for how to add a real one.

## Hardware regression fixture

After a successful physical-device session, save a sanitized BLE
notification capture in `fixtures/` and add a decoder test against it, then
update this profile's `status`. Never commit Wi-Fi credentials, device
secrets, or cloud tokens.