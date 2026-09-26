# Fixtures

Sanitized BLE notification captures from real Lolan BMS hardware belong
here. Each capture must document the firmware/hardware revision and expected
decoded values in its accompanying decoder test.

No real capture exists yet — the fixtures currently in
`test/test_lolan_bms_decoder/test_main.cpp` are hand-built (a status frame
and a cell-info frame, float32 values produced with the IEEE-754 encoder
the decoder mirrors), not captured from real hardware.