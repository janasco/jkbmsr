# Firmware Downloads

JK BMS Remote public firmware artifacts are published in the public `jkbmsr-releases` repository and served from:

- `https://cdn.jkbmsr.com`

This public release host is for manual downloads, checksum verification, release notes, and public OTA verification material.

Current target:

- `esp32dev`

Public release contents:

- firmware binary
- checksum file
- signed OTA metadata
- release notes
- public verification key

## Canonical Public Paths

- `https://cdn.jkbmsr.com/`
- `https://cdn.jkbmsr.com/firmware/latest.json`
- `https://cdn.jkbmsr.com/firmware/releases.json`
- `https://cdn.jkbmsr.com/ota/latest.json`
- `https://cdn.jkbmsr.com/docs/VERIFY_FIRMWARE.md`
- `https://cdn.jkbmsr.com/CHANGELOG.md`

## Distribution Split

- Use `https://cdn.jkbmsr.com` for manual download and verification.
- Production OTA updates are still delivered through the authenticated cloud API.
- The public release host does not replace dashboard authentication, device authorization, or OTA rollout control.

## Manual Download Flow

1. Open `https://cdn.jkbmsr.com/firmware/latest.json` to confirm the current public version and target.
2. Open `https://cdn.jkbmsr.com/firmware/releases.json` if you need public release history or installer-facing version listings.
3. Download `firmware.bin` and `firmware.sha256` for the matching target directory.
4. Verify the checksum before flashing.
5. Review `release.json`, release notes, and OTA metadata if you are validating a support case or installer workflow.

JK BMS Remote version 1 supports JK-BMS only.
