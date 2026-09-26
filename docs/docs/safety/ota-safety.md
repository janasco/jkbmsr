# OTA Safety

OTA updates change live battery monitoring firmware. Treat them as controlled maintenance operations.

## Rules

- Confirm the target hardware matches the published release
- Verify the checksum before manual flashing
- Do not install unsigned or unverified firmware
- Keep stable power during updates
- Do not interrupt an in-progress update

## Production OTA Model

JK BMS Remote production OTA uses:

- signed metadata
- SHA-256 firmware verification
- authenticated firmware download through the cloud API

## Scope

JK BMS Remote version 1 supports JK-BMS only.
