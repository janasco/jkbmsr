# Verify Firmware

Use this guide to verify the public OTA verification material for a release.

## Files

For an OTA-capable target, the public material under `https://cdn.jkbmsr.com` is:

- `ota/<target>-latest.json` — signed OTA metadata for the target
- `ota/keys/public/<key id>.pem` — the OTA public verification key

The firmware binaries themselves are not downloadable from this host; they are
installed from the logged-in flasher at <https://web.jkbmsr.com/flash>, which shows
the release checksum and verifies each flashed part.

## Verify Signed OTA Metadata

1. Save the OTA metadata payload fields in this exact order, separated by newlines:

```text
version
targetHardware
releasedAt
sha256
```

2. Base64-decode the `signature` field from `ota/<target>-latest.json`
3. Verify the signature with the published public key

Example verification flow (substitute the values from the metadata file):

```bash
printf '%s\n%s\n%s\n%s' \
  '<version>' \
  '<targetHardware>' \
  '<releasedAt>' \
  '<sha256>' > payload.txt

printf '%s' '<signature>' | base64 -d > signature.bin

openssl dgst -sha256 \
  -verify ota/keys/public/<key id>.pem \
  -signature signature.bin \
  payload.txt
```

Expected output:

```text
Verified OK
```
