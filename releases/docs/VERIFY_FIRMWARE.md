# Verify Firmware

Use this guide to verify public firmware artifacts before flashing manually.

## Files

For firmware `0.1.2` on `esp32dev`, use:

- `firmware/esp32dev/v0.1.2/firmware.bin`
- `firmware/esp32dev/v0.1.2/firmware.sha256`
- `ota/latest.json`
- `ota/keys/public/jkbmsr-ota-p256-20260705.pem`

## Verify SHA-256

Linux:

```bash
sha256sum firmware.bin
cat firmware.sha256
```

macOS:

```bash
shasum -a 256 firmware.bin
cat firmware.sha256
```

The computed checksum must match the published checksum exactly.

## Verify Signed OTA Metadata

1. Save the OTA metadata payload fields in this exact order, separated by newlines:

```text
version
targetHardware
releasedAt
sha256
```

2. Base64-decode the `signature` field from `ota/latest.json`
3. Verify the signature with the published public key

Example payload for `0.1.2`:

```text
0.1.2
esp32dev
2026-07-05T07:14:03Z
24c0d60d08894d333e954ec226cbed69b80de8729bdcbec57e052bc4cfe2bfe2
```

Example verification flow:

```bash
printf '%s\n%s\n%s\n%s' \
  '0.1.2' \
  'esp32dev' \
  '2026-07-05T07:14:03Z' \
  '24c0d60d08894d333e954ec226cbed69b80de8729bdcbec57e052bc4cfe2bfe2' > payload.txt

printf '%s' 'MEYCIQC1eMljN4zL+D8sppiFLBCosU8sC72LVvvrUhubNsLPbgIhAIjHqLuJuODOuofha+HPyhzLTY4xfjbzCYCihAkY3YU/' | base64 -d > signature.bin

openssl dgst -sha256 \
  -verify ota/keys/public/jkbmsr-ota-p256-20260705.pem \
  -signature signature.bin \
  payload.txt
```

Expected output:

```text
Verified OK
```
