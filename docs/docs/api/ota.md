# OTA API

```text
GET /api/v1/ota/latest
```

Returns the latest firmware version, release timestamp, download URL, SHA-256 checksum, and OTA metadata signature fields.

Expected metadata fields:

- `version`
- `targetHardware`
- `releasedAt`
- `downloadUrl`
- `sha256`
- `signature`
- `signingKeyId`
- `signatureAlgorithm`
