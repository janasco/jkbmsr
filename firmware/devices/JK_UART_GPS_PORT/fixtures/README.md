# Fixtures

Sanitized raw UART "read all registers" response captures from real JK-BMS
hardware belong here. Each capture must document the firmware/hardware
revision and expected decoded values in its accompanying decoder test.

No real capture exists yet — the only current fixture
(`kStatusFrame` in `test/test_jk_bms_parser/test_main.cpp`) is synthetic.
