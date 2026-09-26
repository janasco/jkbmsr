# Fixtures

Sanitized raw UART frame captures from real JBD-BMS hardware belong here.
Each capture must document the firmware/hardware revision and expected
decoded values in its accompanying decoder test.

No real capture exists yet — the fixtures currently in
`test/test_jbd_bms_parser/test_main.cpp` are hand-built to match the
documented protocol spec, not captured from real hardware.
