# OTA Security

JK BMS Remote OTA releases use signed metadata plus SHA-256 firmware verification.

## Current Scheme

- Signing key ID: `jkbmsr-ota-p256-20260705`
- Signature algorithm: `ecdsa-p256-sha256`
- Firmware target in production: `esp32dev`

## Public Material

This repository may publish:

- Public verification keys
- Signed metadata
- Checksums

This repository must never publish:

- Private signing keys
- Cloudflare secrets
- GitHub release tokens
- Device credentials

## Verification Model

1. OTA metadata is signed
2. Firmware devices verify metadata before update
3. Firmware devices verify the downloaded binary checksum before apply

## Scope

JK BMS Remote version 1 supports JK-BMS only.
