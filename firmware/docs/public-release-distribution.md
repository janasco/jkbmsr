# Public Release Distribution

JKBMSR firmware source remains private.

Firmware is **not** distributed publicly. Since 2026-10-13 the browser flash
bundle is delivered only by the account-gated JK BMS Remote API
(`api.jkbmsr.com/v1/flash/*`), which streams it from the private R2 bucket. The
device OTA channel (`/v1/ota/*`) serves the single OTA image from R2.

## What stays public

The signed OTA metadata and the OTA public key remain public so a release can be
verified independently. They are committed under `releases/ota/` in the public
`jkbmsr` repository and served from `cdn.jkbmsr.com`:

- `ota/<target>-latest.json`
- `ota/keys/public/<key id>.pem`

## What is no longer published

- The four-part browser flash bundle (bootloader / partitions / boot_app0 /
  application) and its manifest
- The `firmware/**` release mirror and `firmware/releases.json` index

The release pipeline stores the flash bundle in R2 under `flash/<target>/v<version>/`
and the OTA image under `firmware/<target>/…`. Neither is committed to this
repository or published to the CDN.

## Rules

- Do not publish firmware source code
- Do not publish private signing keys
- Do not publish Cloudflare or GitHub secrets
- Keep the public OTA metadata aligned with the D1 release row it is derived from
