# Verify Firmware Checksum

Before manually flashing firmware, verify the published SHA-256 checksum.

## Required Files

- firmware binary
- matching `firmware.sha256`

## Linux

```bash
sha256sum firmware.bin
cat firmware.sha256
```

## macOS

```bash
shasum -a 256 firmware.bin
cat firmware.sha256
```

The computed value must exactly match the published checksum.

If it does not match, do not flash the firmware.
