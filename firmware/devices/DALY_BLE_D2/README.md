# Daly Smart BMS — D2/Modbus BLE protocol

Compatibility profile for Daly's H/K/M/S-series BLE protocol. This is a
**different, incompatible protocol** from [`DALY_UART_0xA5`](../DALY_UART_0xA5/)
— same brand, two unrelated protocol families (this one's frame starts
`0xD2`; the classic consumer UART series starts `0xA5`). Also distinct from
the "P81" BLE variant (frame start `0x81`/`0x51`) some "DL-Fxxx"-advertised
units use instead — not implemented here.

- Hardware revisions: the whole D2/Modbus BLE protocol family
- Protocol family: `DALY_D2_BLE` — Modbus-style function/register-address
  reads, CRC16-Modbus checksum
- Connection: BLE, service `0xFFF0`, notify characteristic `0xFFF1`, write
  characteristic `0xFFF2` (two characteristics, unlike JK's single one)

The implementation is split the same way JK's is: `src/bms/DalyD2Decoder.*`
(pure frame decode, hardware-free) and `src/bms/DalyBmsBleClient.*` (NimBLE
connection/scan/notify transport). Ported from `syssi/esphome-daly-bms`'s
`daly_bms_ble.cpp` (Apache-2.0) — see `docs/third-party-attribution.md`.
Decoder coverage is in `test/test_daly_d2_decoder/`.

## Scope of this first pass

Only the "status" register read (address `0x0000`) is implemented — a
single request returns cell voltages, temperatures, pack
voltage/current/SOC, cycle count, and charge/discharge/balance state all at
once. Settings, version, and balancer-switch commands are not implemented,
nor is the P81 protocol variant. The transport requests a fixed 62-register
response (129 bytes); `DalyD2Decoder` itself also supports decoding the
larger 80-register response some units send regardless of what's requested
(165 bytes, carries balancing current/MOSFET temp/board temp too), but the
transport doesn't yet reassemble that size automatically — see
`src/bms/DalyBmsBleClient.h`'s `kAssemblyTargetSize` comment.

## Status: synthetic-fixture-only

The only fixtures exercising this decoder are hand-built to match the
protocol's documented frame layout, not captured from real hardware. See
`fixtures/README.md` for how to add a real one.

## Hardware regression fixture

After a successful physical-device session, save a sanitized BLE
notification capture in `fixtures/` and add a decoder test against it, then
update this profile's `status`. Never commit Wi-Fi credentials, device
secrets, or cloud tokens.
