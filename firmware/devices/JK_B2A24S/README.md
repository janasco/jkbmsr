# JK-B2A24S

Compatibility profile for the JK-B2A24S hardware (24-cell JK02 frame layout,
hardware version major < 11).

- Hardware revision: < 11 (selects the 24-cell frame layout; see
  `hardwareVersionIs32s()` in `src/bms/Jk02Decoder.cpp`)
- Protocol family: JK02_24S
- Connection: Bluetooth Low Energy
- Service UUID: `FFE0`
- Notify/write characteristic UUID: `FFE1`
- Address selection: configured MAC or strongest compatible advertisement

The implementation remains shared in `src/bms/Jk02Decoder.*` and
`src/bms/JkBmsBleClient.*`. Decoder coverage is in
`test/test_jk02_decoder/`; this keeps fixes common while the profile makes the
models affected by a shared change visible.

## Status: protocol-verified, not yet hardware-tested by us

Unlike `JK_B1A8S10P` (`hardware-tested`: a real bring-up with our own gateway
hardware), this profile's 24-cell decode path is verified only against a
sanitized third-party device capture (`kCellInfo24s` in
`test/test_jk02_decoder/test_main.cpp`, originally documented in
`syssi/esphome-jk-bms`, Apache-2.0 — see `docs/third-party-attribution.md`).
The offset math and checksum are confirmed correct against that real capture,
but no one has yet run this firmware against a physical JK-B2A24S over our
own gateway hardware.

## Hardware regression fixture

After a successful physical-device session, save a sanitized JK02 notification
capture in `fixtures/` and add it to the decoder test, then update this
profile's `status` to `hardware-tested`. Never commit Bluetooth addresses,
Wi-Fi credentials, device secrets, or cloud tokens.
