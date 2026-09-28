# Deploying

**There is no CI in this repository.** No GitHub Actions, no hosted runners, no
automatic deploys, no green tick on a pull request. GitHub is used for source
code storage only. Every build, every check and every publish to Cloudflare is a
person running a command.

That has one consequence worth stating plainly: nothing catches a broken change
except the person who made it. Run [`scripts/check-all.sh`](scripts/check-all.sh)
before you open a pull request.

| Task | Command | Publishes? |
| :--- | :--- | :--- |
| Check every component | `scripts/check-all.sh --run` | no |
| Check one component | `scripts/check-all.sh --run --only firmware` | no |
| Build the docs, publish nothing | `scripts/deploy-docs.sh --build-only` | no |
| Publish the docs site | `scripts/deploy-docs.sh --deploy` | `docs.jkbmsr.com` |
| Package the release CDN, publish nothing | `scripts/deploy-releases.sh --build-only` | no |
| Publish the release CDN | `scripts/deploy-releases.sh --deploy` | `cdn.jkbmsr.com` |
| Environment check on its own | `scripts/preflight.sh --project jkbmsr-docs` | no |
| Firmware checks only | `firmware/scripts/run-checks.sh` | no |
| Firmware OTA release | `firmware/scripts/release.sh <version>` | R2, D1, GitHub Release |

With no arguments, the two deploy scripts run a **dry run**: they validate,
print the exact commands they would run, publish nothing, and exit 0. You have
to pass `--deploy` to publish anything. `scripts/check-all.sh` behaves the same
way: bare, it prints the plan and runs nothing.

---

## The host map

Read this before every deploy. A Pages project name is load-bearing, and a
deploy aimed at the wrong one publishes nothing at best.

| Host | What serves it | Notes |
| :--- | :--- | :--- |
| `jkbmsr.com` | **WordPress** (`jkbmsr-wp`) | **Never a Pages deploy target.** |
| `www.jkbmsr.com` | **WordPress** (`jkbmsr-wp`) | **Never a Pages deploy target.** |
| `web.jkbmsr.com` | Pages project `jkbmsr-web` | not this repository |
| `docs.jkbmsr.com` | Pages project `jkbmsr-docs` | `scripts/deploy-docs.sh` |
| `cdn.jkbmsr.com` | Pages project `jkbmsr-releases` | `scripts/deploy-releases.sh` |
| `api.jkbmsr.com` | Cloudflare Worker (`jkbmsr-api`) | not Pages at all |
| `admin.jkbmsr.com` | Pages project `jkbmsr-admin` | not this repository |

The apex is the one that hurts. Deploying a Pages build to `jkbmsr.com` is what
caused the **2026-09-12 outage**, and the host map was wrong in several
internal documents for months before that, which is what made it easy to get
wrong. `scripts/preflight.sh` refuses the apex outright and prints this table
on every failure.

The other half of the rule: **do not rename a Pages project.** `jkbmsr-docs`
and `jkbmsr-releases` are the names the custom domains point at. Renaming one
orphans a live host, and the fix is a DNS change under time pressure.

---

## Credentials

Nothing below is in this repository, by design. See
[CONTRIBUTING.md](CONTRIBUTING.md) rule 2.

```bash
# Cloudflare. Both are required. The account id is not optional.
export CLOUDFLARE_ACCOUNT_ID=9c686ab673caa0f69af5bee930392670
export CLOUDFLARE_API_TOKEN='...'      # never commit, never paste into an issue
```

| Credential | Needed for | Where it comes from | Permissions |
| :--- | :--- | :--- | :--- |
| `CLOUDFLARE_API_TOKEN` | every `--deploy` | Cloudflare dashboard → Profile → API Tokens. On the build host a working copy lives in `jkbmsr-private/backend/.env` (mode 0600, `jkbmsr`-owned). **Source it, never copy it.** Roll at <https://dash.cloudflare.com/profile/api-tokens> | Account → Cloudflare Pages: Edit; plus Workers R2 Storage: Edit and D1: Edit for firmware |
| `CLOUDFLARE_ACCOUNT_ID` | every `--deploy` | Cloudflare dashboard → account overview | — |
| `OTA_SIGNING_PRIVATE_KEY_B64` | firmware release only | **Offline escrow. Not in this repository, not in any repository.** Base64 of the ECDSA P-256 PEM | anyone holding it can sign firmware your devices will trust |
| `OTA_SIGNING_KEY_ID` | firmware release only | published alongside the signed metadata; currently `jkbmsr-ota-p256-20260705` | — |

### Why `CLOUDFLARE_ACCOUNT_ID` is mandatory

The API token can see **both** the pre-migration and the post-migration
Cloudflare account, and both accounts have same-named R2 buckets and same-named
Pages projects. With only the token exported, `wrangler r2 object put --remote`
silently wrote to the **old** account's bucket. The readback then made it worse:
`wrangler r2 object get --remote`, also pointed at the wrong account, returned a
perfect match — while the live API, bound to the new account, kept serving the
old object. That is a misroute that looks like success, and it cost a failed
publish of Pro 1.3.28.

So `scripts/preflight.sh` checks the account id against the literal
`9c686ab673caa0f69af5bee930392670` and refuses anything else, including "unset".
If you ever do need to target the other account, change the literal in
`scripts/preflight.sh` on purpose, having read this section.

---

## Deploying the documentation site

```bash
# 1. Read-only: validate, and see what a real deploy would do.
scripts/deploy-docs.sh

# 2. Build it without publishing.
scripts/deploy-docs.sh --build-only

# 3. Publish. This is the only step that touches Cloudflare.
scripts/deploy-docs.sh --deploy
```

What that does, in order:

1. `scripts/preflight.sh --project jkbmsr-docs` — credentials, account id,
   target project, wrangler CLI surface.
2. Verify the docs component exists and has the expected entry points.
3. Verify the markdown inventory (a floor of 10 files; the real check is the
   build, which fails on a dead internal link).
4. `npm ci` in `docs/`, then `npm run docs:build`. VitePress dies on a broken
   internal link or a failed SSR render, which is the check the old validate job
   never got to run because it only counted files.
5. Stage the build output (`docs/docs/.vitepress/dist`) into `docs/dist/`. The
   old pipeline filled that directory by unpacking the `jkbmsr-docs-dist`
   artifact; it is cleared first here, because CI got a fresh checkout for
   every run and a local working tree does not. `docs/dist` is the directory
   that gets uploaded, so it is also the thing to inspect before deploying.
6. `npx wrangler pages deploy dist --project-name jkbmsr-docs --branch main`
7. Verify (see below).

Useful flags: `--skip-install` (assume `node_modules` is current), `--no-verify`.

## Publishing the docs on the apex, at `jkbmsr.com/docs/`

The same documentation build is published in **two** places, and they are not
the same deployment:

| Where | Path | Pages project | Built and staged by |
|---|---|---|---|
| `https://docs.jkbmsr.com` | `/` | `jkbmsr-docs` | `scripts/deploy-docs.sh` (above) |
| `https://jkbmsr.com/docs/` | `/docs/` | `jkbmsr-marketing` (the apex) | `scripts/stage-docs-at-apex.sh` (below) |

One VitePress build serves both, so `docs/docs/.vitepress/config.ts` sets
`base: '/docs/'`. That value is the whole risk in this arrangement: with no
`base`, VitePress defaults to `/` and every asset URL it emits is
root-absolute, so a copy placed under `/docs/` resolves every stylesheet, the
theme and every internal link against the **apex root** instead. Nothing throws.
The pages render unstyled and the links go to the marketing site.

**`docs.jkbmsr.com` is unaffected by any of this.** It deploys the same files at
their own root, where the same `/assets/…` URLs are correct, and it keeps
working whether or not the apex copy is deployed. Retiring it is a separate
decision; nothing here depends on it.

### The two checkouts, and why that matters

The marketing site is **not** in this repository. It is a separate checkout at
`/home/jkbmsr/jkbmsr-site` with its own git history, and its build output is
`dist/client`, which is what gets uploaded to Pages. So this procedure spans two
directories and two repositories, and the order is load-bearing:

```bash
cd /home/jkbmsr/jkbmsr-site && npm run build     # 1. empties dist/client
cd /home/jkbmsr/jkbmsr
scripts/stage-docs-at-apex.sh --test             # 2. stages + verifies (publishes nothing)
cd /home/jkbmsr/jkbmsr-site
npm run preview                                  # 3. browse http://localhost:4321/docs/
#    ... stop preview ...
rm -f dist/client/wrangler.json && rm -rf dist/client/.wrangler   # 4
scripts/preflight.sh --project jkbmsr-marketing                   # 5
npx wrangler@4.118.0 pages deploy dist/client \
  --project-name jkbmsr-marketing --branch main                   # 6
```

Step 1 **must** precede step 2. `astro build` empties `dist/client` on every
run, so a stage performed first is deleted without a word. Step 4 **must**
follow step 3: the Astro Cloudflare adapter writes `dist/client/wrangler.json`,
and Pages rejects the deployment with it present, but `astro preview` needs that
file to know a build exists. Those two facts pull in opposite directions and
that is the whole reason the ordering is written down here rather than left to
memory.

`wrangler` is pinned at **4.118.0** deliberately. A bare `npx wrangler` floats
to the newest published version, and 4.141.0 broke a run on 2026-09-26 when
4.118.0 was known-good.

### What step 2 verifies

`scripts/stage-docs-at-apex.sh` runs `scripts/stage-docs.mjs`, which stages the
build into `dist/client/docs/` and then checks nine things. It publishes nothing
and needs no credentials. The ones that are easy to get wrong:

- **Every URL the staged pages reference is resolved against the merged tree**,
  not against the docs tree, and not merely for the `/docs/` prefix. A prefix
  check alone passes `/docs/docs/favicon.svg` — a URL this change actually
  produced, because `themeConfig.logo` is base-prefixed by the theme while `head`
  entries are emitted verbatim — and it was the existence check that caught it.
- **The extractor proves itself first**, and a run that extracts nothing is a
  failure rather than a pass.
- **The copy is compared by sha256**, not by existence.
- **A wrong `base` is fatal.** With `base` disabled the run refuses with 1,704
  escaping references. Measured, not assumed.
- **`_headers` and `_redirects` are accounted for, rule pair by rule pair.** The
  staged tree adds neither, so `/docs/` is governed by the rules that already
  govern the rest of the site. All 36 rule pairs in the apex `_headers` are
  checked for two rules that could set the same header on the same path; the
  answer is zero, so there is nothing for Pages' append behaviour to append.
- **The marketing site's own files are compared before and after** and must be
  byte-identical.
- **`/docs/sitemap.xml` is generated from the files that exist**, not from a
  list, and every `<loc>` in it is resolved and checked against the apex's own
  child sitemaps for overlap.

`scripts/stage-docs.test.mjs` (run by `--test`) shows every one of those guards
failing on input that should make it fail. A negative result from a check that
cannot fail reads as assurance, which is the failure mode this project has hit
three times in one session.

Two warnings are expected and are not defects. Both are decisions that belong to
the marketing repository, and the script says so rather than making them:

1. The apex `sitemap.xml` index does not reference `/docs/sitemap.xml`, and
   `robots.txt` advertises only `/sitemap.xml`. Add `/docs/sitemap.xml` to
   `CHILD_SITEMAPS` in `src/lib/sitemap.ts`, or a `Sitemap:` line to
   `src/pages/robots.txt.ts` — otherwise the docs sitemap exists and nothing
   points a crawler at it.
2. Nothing on the apex links to `/docs/`, and 147 links point at
   `https://docs.jkbmsr.com` instead. Until they are repointed, `/docs/` is an
   orphan *and* a byte-for-byte duplicate of the subdomain, with no canonical
   declared on either.

### Two things about the apex's headers worth knowing before you touch them

- The apex's `/*` CSP reaches `/docs/**`. It has no `'unsafe-inline'` and no
  nonce, and VitePress emits four inline `<script>` elements per page — one of
  which, `check-mac-os`, is pushed unconditionally by VitePress with no config
  switch to suppress it. So the docs cannot be made CSP-clean by configuration.
  The staging step resolves that by moving each unique inline body to a
  same-origin file under `/docs/assets/`, which `script-src 'self'` already
  permits, and the apex's CSP is **not** changed. The alternative — a `/docs/*`
  rule relaxing `script-src` for the docs — would put a second
  `'unsafe-inline'` into a file whose own comment says there is exactly one.
- **Do not verify header behaviour on `astro preview`.** Measured on this host: a
  `/docs/*` rule setting a header the `/*` rule also set produced 14 headers with
  no duplication, and the preview reported parsing 10 header rules. The local
  emulator picks the most specific match; the production edge appends. The check
  that matters is the rule-pair check in `stage-docs.mjs`, and the observation
  that matters is over a raw TLS socket with `scripts/raw-headers.mjs` — HTTP
  joins repeated header fields with `", "`, so a client library cannot see a
  duplicate at all. That is how the two-media-type `content-type` survived here.

### Verifying it from the serving layer, not the build

```bash
node scripts/resolve-over-http.mjs http://localhost:4321   # against a preview
node scripts/resolve-over-http.mjs https://jkbmsr.com       # after publishing
node scripts/raw-headers.mjs --self-test                   # prove the instrument first
node scripts/raw-headers.mjs --scheme https jkbmsr.com / /docs/ /feed/ /feed/atom/
```

`resolve-over-http.mjs` crawls `/docs/` by link, requests every URL the pages
and the stylesheets reference, and reports the **status** — 3xx included and
never followed silently, because a link that works only after a redirect is a
different thing from a link that works. It also reports pages that exist but
that nothing links to: there is currently one,
`/docs/ui_ux_design_system_guide`, which the derived sitemap lists and no page
links to.


## Deploying the release CDN

```bash
scripts/deploy-releases.sh                # dry run
scripts/deploy-releases.sh --build-only   # package into releases/dist only
scripts/deploy-releases.sh --deploy       # publish
```

What that does, in order:

1. `scripts/preflight.sh --project jkbmsr-releases`.
2. Validate the required files, and for every
   `releases/firmware/<target>/latest.json`: the version directory,
   `firmware.bin`, `firmware.sha256`, `flash-manifest.json`, and — for
   OTA-capable targets — the bootloader, partition table, `boot_app0`, the signed
   `releases/ota/<target>-latest.json` and the OTA public key. `publicBaseUrl`
   must be `https://cdn.jkbmsr.com`.
3. `python3 scripts/validate_release_index.py` —
   `releases/firmware/releases.json` against every target's `latest.json` and
   every manifest.
4. `sha256sum -c firmware.sha256` for each target's current version.
5. Package into `releases/dist/`: `index.html`, `_headers`, `_redirects`, a
   freshly generated slim `releases/firmware/releases.json`, each target's
   `latest.json` and its current `v<version>/` directory, plus `mobile/` and
   `ota/` with the `.apk`/`.aab` files removed (Cloudflare Pages caps a single
   file at 25 MiB and the signed AAB is 40+ MiB; those ship as GitHub Release
   assets instead).
6. `npx wrangler pages deploy dist --project-name jkbmsr-releases --branch main`
7. Verify every target's `firmware.bin` over HTTP against the local bytes.

`releases/dist` is wiped and rebuilt on every run. CI got a fresh checkout, so
its `dist` could only ever hold the current build; a local working tree can
leave a previous firmware version behind, and on this CDN the URL *is* the
version number, so a stale directory is a live download of the wrong bytes.

## Cutting a firmware OTA release

Firmware releases are the one job that is not "deploy a static directory": the
binary goes to R2, the metadata row goes to D1, devices fetch it through
`api.jkbmsr.com`, and only then does the public mirror get refreshed. The
procedure is `firmware/scripts/release.sh`; the narrative version of it is
`firmware/docs/manual-release-runbook.md`.

What you must supply:

| Input | Notes |
| :--- | :--- |
| A strict `MAJOR.MINOR.PATCH` version in `firmware/include/FirmwareVersion.h` | bump it before you start; a malformed string is rejected rather than interpolated into D1 SQL, object keys and release metadata |
| PlatformIO 6.1.19 | `pip install "platformio==6.1.19"` |
| `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` | R2 bucket `jkbmsr-firmware`, D1 database `jkbmsr` |
| `OTA_SIGNING_PRIVATE_KEY_B64` | **not in this repository.** Base64 of the ECDSA P-256 private key PEM. Keep it offline; anyone holding it can sign firmware your devices trust |
| `OTA_SIGNING_KEY_ID` | currently `jkbmsr-ota-p256-20260705`. Bump only as part of a key rotation |
| The OTA public key | `firmware/docs/ota-signing-public-key.pem`, published to `releases/ota/keys/public/<key id>.pem` |

Order of operations:

```bash
scripts/check-all.sh --run --only firmware           # actually execute the suites
firmware/scripts/release.sh 0.9.2 --dry-run          # read the whole plan first
firmware/scripts/release.sh 0.9.2                    # sign, R2, D1, GitHub release, mirror
scripts/deploy-releases.sh --deploy                  # publish cdn.jkbmsr.com
firmware/scripts/release.sh 0.9.2 --skip-build --no-publish --verify-cdn --yes
firmware/scripts/test-production-ota.sh              # signature + checksum, live API
```

The version is an explicit argument and must be a strict `MAJOR.MINOR.PATCH`
that already matches `kFirmwareVersion` in `firmware/include/FirmwareVersion.h`
— the script refuses to run if the header and the argument disagree, so bump
the header first. Useful flags: `--target <targetHardware>` to release one
hardware model, `--skip-build` to re-publish a build already staged under
`firmware/.pio/release/`, `--no-publish` to stop before any Cloudflare write,
`--no-commit` / `--no-push` to keep the generated `releases/` mirror local, and
`--verify-cdn` to do a real HTTP read of the published copies.

`release.sh` writes the public mirror files into `releases/` and commits them,
but it cannot publish the CDN: that is a Pages project, and you deploy it with
`scripts/deploy-releases.sh`. That split is deliberate — the mirror commit and
the CDN deploy are separate acts, and the second one is the only one a customer
can observe. `--verify-cdn` gives you the same hash comparison over HTTP that
`scripts/verify-publish.py` does, so use whichever you have in front of you.

`releases/docs/VERIFY_FIRMWARE.md` documents the signature payload layout that
devices verify: version, target hardware, release time and SHA-256, newline
separated, signed with ECDSA P-256/SHA-256.

A rollback is a D1 metadata change, not an artifact change: set the bad
version's `is_latest` to 0 and restore the previous good version for the same
target. Do not overwrite released firmware objects.

---

## Verifying a deploy

**Always: a real HTTP read of the public URL, hashed, compared against the local
file. Never a `wrangler ... get` readback.**

`scripts/deploy-docs.sh --deploy` and `scripts/deploy-releases.sh --deploy` do
this automatically via `scripts/verify-publish.py`, retrying a few times for
edge propagation. To check by hand:

```bash
# docs
python3 scripts/verify-publish.py \
  --url https://docs.jkbmsr.com/index.html \
  --file docs/dist/index.html

# release CDN: index, the index the flasher reads, and every target's binary
python3 scripts/verify-publish.py \
  --url https://cdn.jkbmsr.com/index.html --file releases/dist/index.html \
  --url https://cdn.jkbmsr.com/firmware/releases.json --file releases/dist/firmware/releases.json
```

Why not a wrangler readback:

- `wrangler r2 object get` defaults to **local** storage. Without `--remote` it
  reads a local directory and will happily report a match against an object the
  edge never received.
- Even with `--remote`, it reads whichever account the environment points at —
  which is exactly the two-account trap above.
- The URL wrangler prints after a Pages deploy is a deployment-specific preview
  URL. Reading it proves the upload landed, not that the custom domain serves it.

`curl` is not used anywhere in this repository and must not be added: it is
broken on the build host (its config throws `ORDER: parameter null or not set`).
Every HTTP read here goes through Python's `urllib`.

If a hash mismatches immediately after a deploy, that is usually edge
propagation, not a failed upload — the script retries. If it still mismatches,
compare `releases/dist` against the deploy output on your own terms before
assuming the CDN is serving the wrong thing.

---

## Preflight and troubleshooting

Run `scripts/preflight.sh --project <name>` on its own whenever something
behaves oddly. It prints the account it would target, the wrangler version, and
the CLI surface these scripts depend on.

Both deploy scripts also warn — without failing — when the current branch is not
`main` or when the working tree has uncommitted changes. The old workflows only
ever deployed from `main`, and only ever deployed what was committed; a script
can only tell you, not stop you, so it tells you.

**`pages deploy` refuses, or the deploy lands but the host does not change.**
Check the project name against the host map above first. Then check that
`CLOUDFLARE_ACCOUNT_ID` is set: without it you may have deployed to the other
account, where the same project name exists and the change is invisible from
here. Verify with a real HTTP read before assuming either way.

**`wrangler: command not found`, or the first run is slow.** The scripts use
`npx wrangler`, which downloads wrangler into the npx cache on first use. Pin it
for a reproducible deploy with `WRANGLER_CMD="npx wrangler@4.118.0"`.

**`r2 object list` does not exist.** Correct — it is not part of wrangler.
Enumerate R2 through the REST API,
`GET /accounts/<account id>/r2/buckets/<bucket>/objects`, which has the useful
property that the account id is explicit in the URL, so you know which account
answered.

**A firmware publish appears to succeed but the live API serves the old
binary.** Almost always the two-account trap: token exported, account id not.
Re-export `CLOUDFLARE_ACCOUNT_ID`, re-upload with `--remote`, and confirm with an
HTTP read of the authenticated download route rather than a wrangler readback.

**Release uploads 500 intermittently.** Uploads must be streamed as a raw body
(`?version=&sha256=`), not sent as `multipart/form-data`; a 55–70 MB APK
buffered through a Worker hits the memory limit. Retrying used to paper over
this. It applies to the app release scripts, not to the CDN deploy.

**A scheduled job appears not to run.** `/etc/cron.d` entries do work on the
build host, but a probe can lie: if the target user cannot write the log file,
the redirection fails before the script runs. Check the path is writable by the
job's user.

**`flutter` not found when checking the apps.** `export
PATH=$PATH:/home/jkbmsr/flutter/bin`. `scripts/check-all.sh` adds that directory
automatically when `flutter` is not already on PATH.

**A pull request looks unverified.** It is. There is no CI.
`scripts/check-all.sh --run` is the substitute, and `SKIP` in its table is not
`PASS`.
