# Verify Firmware Checksum

The browser flasher verifies every part it writes against the release's
published SHA-256 before writing it, and shows the release checksum for the
build it is about to install. You do not need to download a file manually —
`cdn.jkbmsr.com` does not serve firmware binaries.

## If you have a firmware file (advanced / OTA inspection)

```bash
sha256sum firmware.bin
```

macOS:

```bash
shasum -a 256 firmware.bin
```

Compare the computed value against the checksum shown in the flasher, or against
the `sha256` field in the signed OTA metadata (`ota/<target>-latest.json`).

If it does not match, do not flash the firmware.

See [Firmware Downloads](/firmware/downloads) for installation and
[Verify Firmware](/firmware/ota-validation) for signature verification.
