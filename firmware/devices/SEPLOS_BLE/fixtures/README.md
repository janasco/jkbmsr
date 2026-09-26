# Fixtures

Sanitized BLE "single machine data" response captures from real Seplos BMS
hardware belong here. Each capture must document the firmware/hardware
revision and expected decoded values in its accompanying decoder test.

No real capture exists yet — the fixture currently in
`test/test_seplos_ble_decoder/test_main.cpp` is hand-built to match the
documented protocol spec, not captured from real hardware.
