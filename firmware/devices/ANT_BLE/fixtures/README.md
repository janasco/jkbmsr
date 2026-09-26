# Fixtures

Sanitized BLE status-response captures from real ANT Smart BMS hardware
belong here. Each capture must document the firmware/hardware revision and
expected decoded values in its accompanying decoder test.

No real capture exists yet — the fixture currently in
`test/test_ant_bms_decoder/test_main.cpp` is hand-built (an ANT 2021 status
frame, CRC-16/MODBUS computed by an independent script), not captured from
real hardware.