# Fixtures

Sanitized BLE notification captures from real KS48100 BMS hardware belong
here. Each capture must document the firmware/hardware revision and expected
decoded values in its accompanying decoder test.

No real capture exists yet — the fixtures currently in
`test/test_ks_bms_decoder/test_main.cpp` are hand-built (a status frame and a
cell-voltage frame), not captured from real hardware.