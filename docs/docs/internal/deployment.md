# Internal Deployment

JKBMSR Cloud is planned for Cloudflare Workers, D1, R2, and Pages.

## Current Public Domains

- `jkbmsr.com`
- `app.jkbmsr.com`
- `api.jkbmsr.com`
- `docs.jkbmsr.com`

## Docs Domain State

- Cloudflare Pages project: `jkbmsr-docs`
- Active custom domain: `docs.jkbmsr.com`
- DNS is managed in the `jkbmsr.com` Cloudflare zone

Verified on 2026-07-05 through the Cloudflare Pages project list.

The documentation repository should keep deployment notes aligned with the actual Cloudflare Pages project and custom-domain state.

Cloud data retention policy should stay aligned with the active `jkbmsr-api` maintenance guidance for `telemetry` and `ota_events`.

The production cleanup path now depends on the `jkbmsr-api` scheduled Worker handler and its retention vars.
