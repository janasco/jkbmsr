# jkbmsr-docs

> **Archived — superseded by `jkbmsr-web`.** The `docs.jkbmsr.com` site this
> repository built has moved to `jkbmsr.com/docs`, served from the
> `documentation/` folder in `jkbmsr-web` (VitePress, same as here) as part
> of the same domain consolidation that already absorbed `jkbmsr-site`. This
> repo's content is no longer the live source — **new docs work should go in
> `jkbmsr-web`'s `documentation/` folder, not here.**

Documentation hub for JKBMSR, the JK Battery Management System Remote platform.

This repository tracks product, user, developer, deployment, troubleshooting, firmware, cloud, OTA, and safety documentation for the full JKBMSR ecosystem.

It now also contains the static documentation site source for `docs.jkbmsr.com`.

## Project Status

JKBMSR is now in execution.

Implemented system pieces:

- ESP32 firmware builds with PlatformIO.
- Cloudflare Worker API is deployed at `https://api.jkbmsr.com`.
- Cloudflare D1 schema has grown well beyond the original users/devices/telemetry/alerts/firmware/api_keys set (20 migrations as of this writing) — device config, WiFi management, BLE config, OTA commands, push tokens, licensing, and more.
- Cloudflare R2 stores firmware binaries.
- Cloudflare Pages serves the unified public site + dashboard at `https://jkbmsr.com` from `jkbmsr-web` (`app.jkbmsr.com` is now just a legacy redirect to the apex domain). `jkbmsr-site`, the original separate marketing repo, is archived — its content was absorbed into `jkbmsr-web`.
- OTA release automation is implemented for `jkbmsr-firmware`.
- Android mobile app is released (`jkbmsr-pro`, signed APK/AAB published to `jkbmsr-releases`) — includes QR-code device claiming, device rename, and push notifications on Android.
- `jkbmsr-admin` — internal admin console at `admin.jkbmsr.com`, behind Cloudflare Access + an `is_admin` gate.

Planning-only pieces:

- iOS mobile release (no Firebase config or release pipeline yet for iOS).
- Google Play Store listing (icon/feature graphic exist in `jkbmsr-brand`; no screenshots, listing copy, or privacy policy URL yet).
- Alert-threshold configuration — there is no alert-generation pipeline at all yet; the `alerts` table and dashboard/mobile alert views exist, but nothing currently writes a row into it.
- PCB/enclosure manufacturing files.
- Full production hardening.

## Repository Purpose

`jkbmsr-docs` is the source of documentation for:

- Installers
- Battery owners
- Developers
- Firmware maintainers
- Cloud/backend maintainers
- Hardware designers
- Support/troubleshooting workflows

## Documentation Structure

```text
docs/
  index.md
  product-overview.md
  api/
    index.md
    authentication.md
    devices.md
    telemetry.md
    config.md
    ota.md
  cloud/
    cloud-setup.md
    ota-update-process.md
  firmware/
    downloads.md
    ota-validation.md
    release-notes.md
    supported-hardware.md
    verify-checksum.md
  getting-started/
    device-registration.md
    esp32-gateway-setup.md
    firmware-flashing.md
    jk-bms-wiring.md
    uart-pinout-warnings.md
  internal/
    architecture.md
    deployment.md
    firmware-release-runbook.md
    release-process.md
  safety/
    battery-safety.md
    ota-safety.md
    wiring-safety.md
  troubleshooting/
    index.md
    bms-connection-issues.md
    ota-support-checklist.md
    ota-issues.md
    telemetry-issues.md
    wifi-issues.md
```

## Live System References

- Public site + web dashboard: `https://jkbmsr.com` (`app.jkbmsr.com` redirects here)
- Admin console: `https://admin.jkbmsr.com`
- Cloud API: `https://api.jkbmsr.com`
- Public release artifacts: `https://cdn.jkbmsr.com`
- Firmware repository: `jkbmsr-firmware`
- Cloud repository: `jkbmsr-api`
- Web repository: `jkbmsr-web` (absorbed `jkbmsr-site`, now archived)
- Mobile repository: `jkbmsr-pro`
- Admin repository: `jkbmsr-admin`
- Hardware repository: `jkbmsr-hardware`

## Core Technology Stack

- ESP32 firmware with PlatformIO and Arduino framework
- Cloudflare Workers backend
- Hono TypeScript API framework
- Cloudflare D1 database
- Cloudflare R2 firmware storage
- Cloudflare Pages dashboard hosting
- Next.js, React, TypeScript, TailwindCSS for web
- Flutter for mobile (Android released; iOS not yet)
- HTTPS JSON REST APIs
- JWT-style authentication
- VitePress for docs site generation

## Documentation Maintenance Rules

- Keep user-facing docs separate from internal implementation notes.
- Update API docs whenever endpoint behavior changes.
- Update OTA docs whenever firmware release flow changes.
- Keep safety warnings explicit and conservative.
- Do not document unsupported BMS vendors as available.
- Keep release and rollback runbooks aligned with the manual deploy procedures in
  `DEPLOY.md` at the root of this repository. There is no CI here; the scripts
  in `scripts/` are what actually run.
- Keep the VitePress navigation aligned with the markdown inventory.

## Current Gaps

- Docs need to be reconciled with the newly implemented dashboard user APIs.
- OTA docs should include the authenticated R2 streaming endpoint.
- Public firmware download and verification docs should stay aligned with `jkbmsr-releases`.
- OTA validation docs should keep machine-based and real-hardware checks clearly separated.
- Getting-started docs need real first-device setup and claim flow.
- Troubleshooting docs need real error messages from the cloud and firmware.

## Next Work

- Update API docs to match the production Worker exactly.
- Add an end-to-end setup guide from ESP32 flashing to web dashboard login.
- Add first-release verification notes after the initial production OTA tag.
- Add customer-facing OTA rollback communication guidance.
- Keep the docs custom domain `docs.jkbmsr.com` attached and DNS-backed in Cloudflare Pages.
