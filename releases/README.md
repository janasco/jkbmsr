# jkbmsr-releases

Public release repository for JK BMS Remote distributable artifacts.

JK BMS Remote is an independent remote monitoring project for JK-BMS systems.

This repository is public by design. It is for release binaries, checksums, signed OTA metadata, release notes, and public download documentation.

Public artifact host:

- `https://cdn.jkbmsr.com`

Authenticated OTA delivery remains separate and continues through the JK BMS Remote cloud API. This repository and domain are for public manual downloads and verification material.

## Scope

This repository may contain:

- ESP32 firmware release binaries
- SHA-256 checksum files
- Signed OTA metadata
- Public OTA verification keys
- Release notes and changelogs
- Public download instructions
- Android APK/AAB release artifacts (`mobile/android/`, published by jkbmsr-pro's release workflow — not "future" anymore, this has been live since v1.0.0)

This repository must not contain:

- Firmware source code
- Mobile source code
- Cloud or dashboard source code
- Private signing keys
- GitHub, Cloudflare, or API secrets
- Internal-only architecture material

## Current Published Artifacts

- Firmware targets: one release per gateway hardware model — see
  `firmware/hardware-targets.json` for the current catalog (currently
  `esp32-classic-4mb`, `esp32-c3-4mb`, `esp32-s3-4mb`, `esp32-c6-4mb`,
  `esp8266-uart-lite`, `esp32-s2-4mb`, `esp32-classic-8mb`).
  `esp32-s2-4mb` has no Bluetooth radio at all — it reaches a BMS over
  wired UART only, and the only supported BMS is JK-BMS. `esp32dev` was
  this repo's original single target before the multi-target migration;
  retired, not reused.
- Current published firmware version per target: see
  `firmware/<target>/latest.json` — don't hardcode a version number in
  this file, it goes stale immediately
- OTA signing key ID: `jkbmsr-ota-p256-20260705`
- OTA signature algorithm: `ecdsa-p256-sha256`
- Mobile: signed Android APK + AAB under `mobile/android/`, published by
  `jkbmsr-pro`'s release workflow on every version tag — **not** deployed
  to Cloudflare Pages (it caps files at 25 MiB; the AAB alone is 40+ MiB),
  only committed to this repo and attached to the matching GitHub Release.
  No iOS artifacts yet.

## Repository Layout

```text
firmware/
  esp32-classic-4mb/
    latest.json
    v0.4.0/
      firmware.bin
      firmware.sha256
      firmware-metadata.json
      release.json
      RELEASE_NOTES.md
  esp32-c3-4mb/    (same shape)
  esp32-s3-4mb/    (same shape)
  esp8266-uart-lite/    (same shape, minus firmware-metadata.json — no OTA)
  esp32-s2-4mb/    (same shape — no BLE on this chip, but keeps OTA)
  esp32-classic-8mb/    (same shape)
  hardware-targets.json
  releases.json
mobile/
  android/
    README.md
ota/
  esp32-classic-4mb-latest.json
  esp32-c3-4mb-latest.json
  esp32-s3-4mb-latest.json
  esp32-s2-4mb-latest.json
  esp32-classic-8mb-latest.json
  keys/
    public/
      jkbmsr-ota-p256-20260705.pem
docs/
  VERIFY_FIRMWARE.md
  OTA_SECURITY.md
  DOWNLOADS.md
CHANGELOG.md
README.md
```

## Related Repositories

- `jkbmsr-firmware`: private source repository for ESP32 firmware
- `jkbmsr-api`: private backend/API repository (Worker service is still
  named `jkbmsr-cloud` internally; the repo itself was renamed)
- `jkbmsr-web`: private source for the unified public site + customer
  dashboard, live at `jkbmsr.com`
- `jkbmsr-pro`: private mobile app source — released, not just planning;
  this repo's `mobile/android/` is where its signed builds land

## Rules

- Publish only artifacts intended for customer or installer consumption.
- Keep release metadata aligned with the production OTA release.
- Never publish private signing material.
- Supported BMS: JK-BMS only, over wired UART. Other vendor decoders exist
  internally in the firmware and are retained for reuse, but they are not
  support claims and must never be published as supported. A gateway
  hardware target with `capabilities.ble: false` (currently
  `esp8266-uart-lite` and `esp32-s2-4mb`) has no Bluetooth radio and so
  reaches JK-BMS over wired UART only — never describe a no-BLE target as
  supporting Bluetooth.

## Deployment

- Cloudflare Pages project: `jkbmsr-releases`
- Public custom domain: `cdn.jkbmsr.com`
- Source branch: `main`
- Deployed by hand: `scripts/deploy-releases.sh` (see `DEPLOY.md`)

The Cloudflare Pages deployment should publish this repository as a static artifact mirror only. Do not place authenticated APIs, upload handlers, or private operational tooling behind this domain.

## Publishing Model

- `cdn.jkbmsr.com` is the canonical anonymous host for manual downloads.
- `api.jkbmsr.com` remains the authenticated OTA channel for managed devices.
- `jkbmsr-firmware` is the private source of truth for firmware source, release generation, and OTA signing.
- Public artifacts mirrored here must match the release metadata published by the production OTA flow.
- `firmware/releases.json` should remain the public history index for release pages, installer tooling, and the marketing downloads page.

## Maintainer Checklist

Before merging public artifact updates:

1. Confirm the firmware binary, checksum, and public metadata all describe the same version.
2. Confirm each `firmware/<target>/latest.json` points at the current public version for that target.
3. Confirm each `ota/<target>-latest.json` exposes only public verification material.
4. Confirm no private keys, Cloudflare tokens, or internal-only files were added.
5. Confirm links on `index.html` and docs still resolve under `https://cdn.jkbmsr.com`.
6. Run `python3 scripts/validate_release_index.py` to verify every `firmware/<target>/latest.json`, `firmware/releases.json`, and manifest files stay aligned.
