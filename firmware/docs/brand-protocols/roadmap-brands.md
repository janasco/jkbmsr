# Roadmap brands — analysis notes (not milestone 1)

Cross-validation scans for the four brands outside milestone 1. Each notes the blocker and
what a future port must reuse. Re-scan pinned working copies before scheduling.

## Offgridtec (esphome-ogt-bms @ dfc45dd)

- BLE-only. Device demands a **per-device encryption key** (`esphome: -> ogt_bms:
  encrypt_key:` in config) burned into the BMS at manufacture; the app performs custom
  byte manipulation with that key over every command/response frame.
- Service/characteristic pairing is standard, but every payload (request + telemetry) is
  transformed with the device key. Wrong key = garbage frames, no error channel.
- Blocker for milestone 1: per-device key provisioning UX doesn't exist in the app flow;
  on first connect the firmware would need a "key entry" path. All other milestone-1
  brands need no keying. Defer until app supports key input.

## Topband v1 (esphome-topband-bms @ ed0da48)

- BLE-only and **purely passive**: the device pushes 32-byte frames on a `~2 s` cadence on
  notify characteristic `0xFFE4` of service `0xFFE0`; there is **no polling** and no
  request frame. SOF `0x5E`, then frame type (0x0101 status / 0x0102 charger info /
  0x0103 misc), big-endian 16-bit samples.
- Client is a listener: subscribe, buffer to SOF, decode. Perfect for the event-driven
  path but different from our poll clients (no command queue, no auth, no write).
- Blocker for milestone 1: transport pattern differs enough (push-only) that it wants its
  own lifecycle test; also v2/v3 exist in separate forks with different frame maps — the
  deployed hardware vintage must be detected first. Defer.

## PACE (esphome-pace-bms @ db83caa)

- **No BLE.** Modbus RTU over RS485, 9600 8N1, via an external UART→RS485 transceiver
  (the repo's docs ship PDF datasheets for the transceiver wiring). Function codes 3
  (read) / 6+16 (write); float32 big-endian registers; status registers around 0x30001.
- Our firmware has an existing Modbus/UART client capability to reuse, but the boards we
  ship are BLE-first with no RS485 driver on the default target pins.
- Defer until a UART/RS485 hardware add-on variant exists (matches "UART only where it
  already exists" scoping decision).

## virtual-CAN (esphome-virtual-can-bms @ 93af45a)

- Not a BMS client at all — the ESP32 uses `CanbusComponent` + a CAN driver to
  **masquerade as an SMA-compatible external battery** on a Victron/SMA CAN network,
  broadcasting its own SMA-defined PDOs.
- Opposite direction to everything else in `src/bms` (we consume BMS telemetry; this
  fabricates it). Useful later for the "gateway presents itself to an inverter" feature,
  not for the brand-expansion milestone. Defer.