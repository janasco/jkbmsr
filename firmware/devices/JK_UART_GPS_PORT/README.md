# JK-BMS UART GPS Port (all models, software >= 6.0)

Compatibility profile for the wired UART-TTL transport ("GPS" port), shared
across the entire compatible JK-BMS lineup rather than one commercial SKU —
see `docs/jk-bms-connectivity.md` for wiring and protocol details.

- Hardware revisions: all JK-BMS units running BMS software >= 6.0
- Protocol family: 0x4E57 (request/response, "read all registers" command
  `0x06`)
- Connection: wired UART-TTL, 115200 baud, no BMS app password required
- Pins (remappable via remote config): GPIO16 (RX) / GPIO17 (TX)

The implementation is shared in `src/bms/JkBmsParser.*` (register map ported
from `syssi/esphome-jk-bms`, Apache-2.0 — see
`docs/third-party-attribution.md`). Decoder coverage is in
`test/test_jk_bms_parser/`.

## Status: synthetic-fixture-only, not yet validated against any real capture

The only fixture exercising this decoder (`kStatusFrame` in
`test/test_jk_bms_parser/test_main.cpp`) is explicitly synthetic — hand-built
to match the documented register layout, not captured from real hardware
(third-party or our own). This is the single largest remaining gap in JK-BMS
protocol validation: every JK-BMS model that only exposes the GPS/UART port
(no Bluetooth) is currently supported on paper only.

## Hardware regression fixture

After a successful physical-device session over UART, save the sanitized raw
frame bytes in `fixtures/` and add a decoder test against them (see
`JkBmsParser::setRawCaptureEnabled`, which emits exactly this raw frame data
to the debug log for capture), then update this profile's `status` to
`protocol-verified` (third-party/reference capture) or `hardware-tested` (our
own gateway hardware). Never commit Wi-Fi credentials, device secrets, or
cloud tokens.
