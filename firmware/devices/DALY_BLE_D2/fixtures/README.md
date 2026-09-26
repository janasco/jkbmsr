# Fixtures

Sanitized BLE status-response captures from real Daly BMS (D2/Modbus
protocol) hardware belong here. Each capture must document the
firmware/hardware revision and expected decoded values in its accompanying
decoder test.

No real capture exists yet — the fixtures currently in
`test/test_daly_d2_decoder/test_main.cpp` are hand-built to match the
documented protocol spec, not captured from real hardware.
