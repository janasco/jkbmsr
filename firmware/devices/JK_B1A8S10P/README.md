# JK-B1A8S10P

Compatibility profile for the JK-B1A8S10P hardware available for JKBMSR
testing.

- Hardware revision: 11.XW
- Protocol family: JK02_32S
- Connection: Bluetooth Low Energy
- Service UUID: `FFE0`
- Notify/write characteristic UUID: `FFE1`
- Address selection: configured MAC or strongest compatible advertisement
- Wi-Fi management: remotely verified 2.4 GHz migration with automatic rollback (firmware 0.2.6+)

The implementation remains shared in `src/bms/Jk02Decoder.*` and
`src/bms/JkBmsBleClient.*`. Decoder coverage is in
`test/test_jk02_decoder/`; this keeps fixes common while the profile makes the
models affected by a shared change visible.

## Hardware regression fixture

After a successful physical-device session, save a sanitized JK02 notification
capture in `fixtures/` and add it to the decoder test. Never commit Bluetooth
addresses, Wi-Fi credentials, device secrets, or cloud tokens.
