# Seplos Smart BMS — BLE protocol (1101-SPxx/ZH/MZ family)

Compatibility profile for Seplos's BLE protocol. Covers the best-evidenced
protocol family (1101-SP05/SP15/SP16/ZH26/MZ02 and similar, per community
reports). Seplos also ships a separate, much-less-proven V3/EMU10xx BLE
protocol (`seplos_bms_v3_ble` upstream) — **not implemented here**, only one
community report exists for it. No Seplos UART support exists in this
firmware; this profile is BLE-only.

- Hardware revisions: the whole 1101-SPxx/ZH/MZ BLE protocol family
- Protocol family: `SEPLOS_BLE_1101` — length-prefixed frames
  (`0x7E`...`0x0D`), CRC-16/XMODEM checksum
- Connection: BLE, service `0xFF00`, notify characteristic `0xFF01`, write
  characteristic `0xFF02`

**Important**: these are the same UUIDs [`JBD_BLE`](../JBD_BLE/) uses.
Address-less auto-discovery can pick the wrong unit if both a JBD and a
Seplos device are advertising nearby simultaneously. Configure an explicit
`bmsBleAddress` for Seplos devices when this might be a concern — upstream's
own Seplos integration always requires an explicit MAC address for the same
reason, and has no reliable advertised-name prefix the way JK (`JK`) or
Daly (`DL-`) do. As a second line of defense, `SeplosBmsBleClient::loop()`
disconnects and retries against the next-strongest candidate if a
connection produces no valid frame within `kFrameValidationTimeoutMs`
(20s) — a JBD unit exposes the same service but will never answer a
Seplos-formatted status request, so this catches a wrong-vendor lock
within 20 seconds instead of leaving the gateway silently stuck.

The implementation is split the same way JK's and Daly's are:
`src/bms/SeplosBleDecoder.*` (pure frame decode, hardware-free) and
`src/bms/SeplosBmsBleClient.*` (NimBLE connection/scan/notify transport).
Ported from `syssi/esphome-seplos-bms`'s `seplos_bms_ble.cpp` (Apache-2.0)
— see `docs/third-party-attribution.md`. Decoder coverage is in
`test/test_seplos_ble_decoder/`.

## Scope of this first pass

Only the "single machine data" command (`0x61`) is implemented — a single
request returns cell voltages, temperatures, pack voltage/current, SOC,
capacity, cycle count, state of health, and charge/discharge switch state
all at once. Manufacturer-info (device model/hardware/firmware version),
settings, parallel-data, and all write/control commands are not
implemented. A few registers in the single-machine-data frame also aren't
mapped to `BatteryTelemetry` fields (a distinct "battery capacity" register
and port voltage) — no clearly corresponding field exists for them; see the
comments in `src/bms/SeplosBleDecoder.cpp`. Balancing-active state isn't
exposed in this frame at all.

## Status: synthetic-fixture-only

The only fixture exercising this decoder is hand-built to match the
protocol's documented frame layout, not captured from real hardware. See
`fixtures/README.md` for how to add a real one.

## Hardware regression fixture

After a successful physical-device session, save a sanitized BLE
notification capture in `fixtures/` and add a decoder test against it, then
update this profile's `status`. Never commit Wi-Fi credentials, device
secrets, or cloud tokens.
