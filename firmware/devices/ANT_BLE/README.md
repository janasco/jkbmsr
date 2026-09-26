# ANT Smart BMS — BLE protocol (2021-style)

Compatibility profile for ANT's 2021-style BLE protocol: fixed envelopes
(`0x7E 0xA1 ... 0xAA 0x55`) with a CRC-16/MODBUS checksum, addressable via a
single characteristic (`0xFFE1`) used for both writes and notifications.

- Hardware revisions: the whole 2021 BLE protocol family
- Protocol family: `ANT_BMS_2021_BLE` — CRC-16/MODBUS, little-endian values
- Connection: BLE, service `0xFFE0`, characteristic `0xFFE1` (write and
  notify), no separate control characteristic

**Important**: service `0xFFE0` is shared with [`JK_*`](../JK_B1A8S10P/) and
[`LOLAN_BLE`](../LOLAN_BLE/) profiles, both of which this firmware also
speaks. Address-less auto-discovery can pick the wrong unit when devices from
these families advertise near each other. Configure an explicit
`bmsBleAddress` where this is a concern; otherwise the advertised `"ant"` /
`"antbms"` name hint is preferred, and as a second line of defense
`AntBmsBleClient::loop()` disconnects and retries against the
next-strongest candidate if a connection produces no valid frame within
`kFrameValidationTimeoutMs` (20s).

The implementation is split like every other brand here:
`src/bms/AntBmsDecoder.*` (pure frame decode, hardware-free) and
`src/bms/AntBmsBleClient.*` (NimBLE connection/scan/notify transport). Ported
from `syssi/esphome-ant-bms`'s `ant_bms_ble.cpp` (Apache-2.0) — see
`docs/third-party-attribution.md`. Decoder coverage is in
`test/test_ant_bms_decoder/`.

## Scope of this first pass

Only the 2021 *status* response (function `0x11`, answering a status request
with function `0x01`) is decoded. It already carries cell voltages, up to
4 NTC temperatures plus MOSFET/balancer temperatures, pack voltage/current,
SOC, SOH, MOS/balancer state, protection and warning bitmasks, capacities and
instantaneous power all in one frame. The device-info/settings command,
per-command writes (charge/discharge switch, arbitrary current, voltage and
capacity settings) and the older 2019-style protocol are not implemented
(read-only telemetry).

## Status: synthetic-fixture-only

The only fixture exercising this decoder is hand-built to match the
protocol's documented frame layout, not captured from real hardware. See
`fixtures/README.md` for how to add a real one.

## Hardware regression fixture

After a successful physical-device session, save a sanitized BLE
notification capture in `fixtures/` and add a decoder test against it, then
update this profile's `status`. Never commit Wi-Fi credentials, device
secrets, or cloud tokens.