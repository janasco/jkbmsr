# JK BMS Remote release CDN

Source for the public release host served at:

- `https://cdn.jkbmsr.com`

This directory is packaged and published to the Cloudflare Pages project
`jkbmsr-releases` by `scripts/deploy-releases.sh`.

## What this host serves

- The release index page (`index.html`)
- Public documentation (`docs/`)
- **Public OTA verification material**: per-target signed OTA metadata
  (`ota/<target>-latest.json`) and the OTA public key
  (`ota/keys/public/<key id>.pem`)
- Mobile release checksums and notes (`mobile/android/`)

## What this host does NOT serve: firmware

Firmware is **not published here**. Since 2026-10-13 the browser flash bundle
is delivered only by the **account-gated JK BMS Remote API**
(`api.jkbmsr.com/v1/flash/*`), which streams it from the private R2 bucket. The
device OTA channel (`/v1/ota/*`) serves the single OTA image from R2.

There is deliberately no `firmware/` directory in the packaged deploy: the
packaging step in `scripts/deploy-releases.sh` dies if one appears. A historical
`firmware/` mirror may still exist on disk and in git history; it is not
published. See `jkbmsr-private/ops/internal-notes/firmware-delivery-gate-spec.md`.

Installing firmware is done from the logged-in flasher at
`https://jkbmsr.com/flash`.

## Layout

```text
index.html
404.html
_headers
_redirects
docs/
  DOWNLOADS.md
  OTA_SECURITY.md
  VERIFY_FIRMWARE.md
ota/
  <target>-latest.json
  keys/public/<key id>.pem
mobile/
  android/        (checksums + notes; .apk/.aab ship as GitHub Release assets)
```

## Deployment

- Cloudflare Pages project: `jkbmsr-releases`
- Public custom domain: `cdn.jkbmsr.com`
- Source branch: `main`
- Deployed by hand: `scripts/deploy-releases.sh --deploy` (see `DEPLOY.md`)

The Cloudflare Pages deployment publishes a static artifact mirror only. Do not
place authenticated APIs, upload handlers, or private operational tooling behind
this domain.

## Publishing model

- `cdn.jkbmsr.com` is the anonymous host for the release index, docs, mobile
  checksums, and the public OTA verification material. It is **not** a firmware
  host.
- `api.jkbmsr.com` is the authenticated channel: device OTA (`/v1/ota/*`) and
  the account-gated browser firmware API (`/v1/flash/*`).
- `jkbmsr-firmware` (R2 bucket) is the private source of truth for the released
  firmware objects.
- `firmware/scripts/release.sh` writes the per-target OTA metadata and public
  key into `releases/ota/`; it does not write firmware binaries or a
  `firmware/` index into this repository.

## Maintainer checklist

Before merging public artifact updates:

1. Confirm the public OTA metadata (`ota/<target>-latest.json`) and public key
   describe the release the API and D1 also report.
2. Confirm no `firmware/` directory is added back to this tree.
3. Confirm no private keys, Cloudflare tokens, or internal-only files were
   added.
4. Confirm links on `index.html` and docs still resolve under
   `https://cdn.jkbmsr.com`.
