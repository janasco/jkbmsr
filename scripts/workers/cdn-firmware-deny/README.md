# jkbmsr-cdn-firmware-deny

A one-file Cloudflare Worker that makes `cdn.jkbmsr.com/firmware/**` answer
**404**, unconditionally, at the edge.

## What it is

```text
index.js          the Worker (deny /firmware/** on cdn.jkbmsr.com, else pass through)
wrangler.jsonc    name, account id, and the two routes
index.test.mjs    self-test for the deny predicate
```

## Why it exists

Firmware is delivered only by the account-gated API
(`api.jkbmsr.com/v1/flash/*`), which streams it from the private R2 bucket.
Since 2026-10-13 the browser flash bundle is published nowhere public, and the
Pages project that serves this host no longer packages a `firmware/` directory
(`scripts/deploy-releases.sh` dies if one appears).

The origin is clean: a **cache-busted** request (`?cb=<n>`) 404s every
`/firmware/**` path, the project hostname `jkbmsr-releases-1v3.pages.dev` 404s,
the superseded deployments were deleted, and `releases/firmware/**` was stripped
from git history. Yet the **clean** URLs kept returning 200 with pre-cutover
content after **two** "Purge Everything"s. The zone has no cache rules and no
page rules (only an `http_request_dynamic_redirect` ruleset), so it was an
edge-cache quirk keyed to the clean path that a zone purge does not clear.

A request matching a Worker route is answered by `index.js` and **never reaches
the static origin or that cache**, so the block does not depend on the cache
ever being cleared. That is the difference between this and a purge.

### Why not a Single Redirect rule

A Single Redirects rule can only redirect — it cannot answer 404 — and this zone
is on the **Free** plan, where Single Redirects are capped at 10 rules. A Worker
route is the reliable mechanism, and it is the same one that already retires the
`www` and `docs` hosts on this zone (`jkbmsr-www-redirect`,
`jkbmsr-docs-redirect`).

## Routes

```text
cdn.jkbmsr.com/firmware
cdn.jkbmsr.com/firmware/*
```

Both are on zone `jkbmsr.com`. The bare pattern covers the exact path; the
splat covers everything under it. `zone_name` (not a zone id) is used, matching
the other Workers on this zone.

The Worker still re-checks the host and path in code (`isDenied`), so even a
route widened by mistake cannot make it deny a different host's path. Any
request that is not `cdn.jkbmsr.com/firmware…` is passed through unchanged, so
`/ota/**`, `/docs/**`, `/mobile/**` and `/` keep working.

## The project hostname (`jkbmsr-releases-1v3.pages.dev`)

Not covered here, and it does not need to be:

- It **already 404s** `/firmware/**` at the origin, so there is nothing to
  block.
- A Workers route **cannot** be attached to it anyway. Routes are scoped to a
  zone you own, and `*.pages.dev` is Cloudflare's own zone, not `jkbmsr.com`.
  This is not a choice that was skipped; it is not expressible.

If that host ever did serve firmware, the fix would be on the Pages project
(delete the offending deployment / asset), not a route here.

## Deploying

A human runs this. It is a single-file Worker with no dependencies and no build
step:

```sh
cd scripts/workers/cdn-firmware-deny
CLOUDFLARE_ACCOUNT_ID=9c686ab673caa0f69af5bee930392670 \
  npx wrangler@4.118.0 deploy
```

`wrangler.jsonc` pins `account_id`, `main` and both routes, so no `--project`
flag is needed. The API token must be able to **write Worker routes** in account
`9c686ab673caa0f69af5bee930392670`, in addition to Workers Scripts: Edit.

**Do not re-run `scripts/deploy-releases.sh --deploy` expecting this to change.**
That publishes the Pages artifact; it does not touch this Worker. They are two
separate acts, and only the Worker closes the cache gap.

## Rollback

Delete the route or the Worker — either is sufficient, and no data is involved:

```sh
cd scripts/workers/cdn-firmware-deny
npx wrangler@4.118.0 delete      # removes the Worker and its routes
```

With the routes gone, `cdn.jkbmsr.com/firmware/**` falls back to the
`jkbmsr-releases` Pages project, which serves a 404 from its `404.html` for
unmatched paths (the intended state); the risk being closed is only that the
stale edge cache could serve the removed bundle again.

## Verifying after (the human's) deploy

```sh
# must be 404 on a real firmware path
node -e 'fetch("https://cdn.jkbmsr.com/firmware/esp32-classic-4mb/latest.json").then(r=>console.log(r.status))'

# must be unchanged (200 / its normal status)
node -e 'fetch("https://cdn.jkbmsr.com/ota/esp32-classic-4mb-latest.json").then(r=>console.log(r.status))'
```

`curl` is broken on the build host and must not be used; probe with Node or
Python `urllib` as above.

## Maintenance

This file is the public repo's copy and the source of truth for the Worker.
The other Workers on this zone keep a plain-file mirror under
`jkbmsr-private/ops/deploys/<worker>/` with a matching `.md`; this one lives
here because it is part of the public release-CDN story (see
`releases/README.md`).
