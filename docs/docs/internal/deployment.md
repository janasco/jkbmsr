# Internal Deployment

JKBMSR Cloud is planned for Cloudflare Workers, D1, R2, and Pages.

## Current Public Domains

- `jkbmsr.com` (the marketing site and the docs at `/docs/`)
- `web.jkbmsr.com`
- `api.jkbmsr.com`
- `docs.jkbmsr.com` (retired as a browsable copy — 301s to `jkbmsr.com/docs/`)

## Docs Domain State

- Cloudflare Pages project: `jkbmsr-docs` (custom-domain origin)
- `docs.jkbmsr.com` is intercepted by the `jkbmsr-docs-redirect` Worker and
  301s every path to `jkbmsr.com/docs/<path>` (retired 2026-09-29); the Pages
  project is kept, not renamed, so deleting the route is the rollback
- DNS is managed in the `jkbmsr.com` Cloudflare zone

Verified on 2026-07-05 through the Cloudflare Pages project list; the docs
entry was updated on 2026-09-29.

The documentation repository should keep deployment notes aligned with the actual Cloudflare Pages project and custom-domain state.

Cloud data retention policy should stay aligned with the active `jkbmsr-api` maintenance guidance for `telemetry` and `ota_events`.

The production cleanup path now depends on the `jkbmsr-api` scheduled Worker handler and its retention vars.
