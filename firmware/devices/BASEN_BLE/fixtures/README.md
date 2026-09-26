# Fixtures

Sanitized BLE notification captures from real Basen BMS hardware belong
here. Each capture must document the firmware/hardware revision and expected
decoded values in its accompanying decoder test.

No real capture exists yet — the fixtures currently in
`test/test_basen_bms_decoder/test_main.cpp` are hand-built (status, general
info and a cell-voltage chunk; checksums computed by an independent script),
not captured from real hardware.