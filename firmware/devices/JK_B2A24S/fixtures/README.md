# Fixtures

Sanitized JK02 notification captures from real JK-B2A24S hardware belong
here. Each capture must document the firmware/hardware revision and expected
decoded values in its accompanying decoder test.

The 24-cell decode path is currently exercised only by a third-party
reference capture inlined in `test/test_jk02_decoder/test_main.cpp`
(`kCellInfo24s`) — no capture from our own hardware exists in this directory
yet.
