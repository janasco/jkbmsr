# OTA Update Process

The ESP32 checks JKBMSR Cloud for firmware updates.

```text
GET /api/v1/ota/latest
```

The response includes:

- Version.
- Target hardware.
- Release timestamp.
- Download URL.
- SHA-256 checksum.

The firmware download is fetched from the authenticated endpoint:

```text
GET /api/v1/ota/firmware/:firmwareId
```

Expected response headers:

- `X-Firmware-Version`
- `X-Firmware-Target`
- `X-Firmware-SHA256`

Expected signed metadata fields on `/api/v1/ota/latest`:

- `signature`
- `signingKeyId`
- `signatureAlgorithm`

The ESP32 must verify the firmware checksum before applying the update.

Use the dedicated validation guide to separate machine-based production checks from real hardware smoke tests:

```text
/firmware/ota-validation
```

OTA releases are published by a person running the release script, not by CI:

```text
firmware/scripts/release.sh
```

The release tag is `firmware-v<version>`, e.g. `firmware-v0.1.1`, and the
operator procedure is in `DEPLOY.md` at the root of this repository.
