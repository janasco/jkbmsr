# Manual Release Runbook

How to build, check, and release firmware from this repository **by hand**.

This repository does not use GitHub Actions. GitHub is the source store and the
release host; every deploy is run deliberately, from a machine, by a person who
can see what it is about to do. Two scripts replace the two workflows that used
to live in `.github/workflows/`:

| Script | Replaces | What it does |
| --- | --- | --- |
| `scripts/run-checks.sh` | `firmware.yml` — jobs `validate`, `host-tests`, `build`, `build-c6` | profile/target validation, the native host suites, the 25-environment PlatformIO matrix |
| `scripts/release.sh` | `ota-release.yml` — jobs `build-release`, `publish-release` | build, sign, verify, upload to R2, update D1, create the GitHub release, commit the public mirror |

Both are safe to run without side effects: `--dry-run` prints the entire plan
and exits 0 without touching Cloudflare, R2, D1, GitHub, or this repository's
git state.

---

## 0. Prerequisites

- `platformio==6.1.19` on `PATH`, or let `run-checks.sh` install it. **The pin
  is deliberate.** An unpinned PlatformIO broke the firmware matrix for two
  weeks; `run-checks.sh` refuses to build on any other version.
- `python3` (3.12 in CI; anything with `urllib` and `hashlib` works here).
- A host `g++` — the host unit suites and `scripts/check-semver.sh` both compile
  natively. No ESP toolchain and no hardware are needed for either.
- `openssl`, `git`, `gh` (GitHub CLI, authenticated with `contents:write`), and
  `node`/`npx` for `release.sh`.
- `curl` is broken on the release host (its config errors out with
  `ORDER: parameter null or not set`). Every HTTP call in `release.sh` goes
  through Python's `urllib` instead. Do not add a `curl` call to these scripts.

---

## 1. Run the checks

```bash
cd firmware
./scripts/run-checks.sh --dry-run     # print the plan, build nothing
./scripts/run-checks.sh               # the real thing
```

Narrow it while iterating:

```bash
./scripts/run-checks.sh --env esp32-c6-4mb --env idf-secure-c3
```

What it does, in order:

1. **validate** — `python3 scripts/validate-device-profiles.py` and
   `python3 scripts/validate-hardware-targets.py`.
2. **host-tests** — `./scripts/run-host-tests.sh`, which really *executes* the
   unit suites natively under AddressSanitizer + UndefinedBehaviorSanitizer.
   This is the only place firmware unit tests actually run: the PlatformIO
   `pio test` step is compile-only (`--without-testing`), so its `[PASSED]` lines
   are compile results.
3. **build** — every `[env:]` in `platformio.ini` (25 of them), generating the
   Secure Boot v2 *development* key first for the `idf-secureboot*` envs that
   need it, compiling the tests for `dev`, and copying each shipped
   `firmware.bin` into `.pio/artifacts/<env>/` with its SHA-256. A leg that
   "succeeds" without producing a `.bin` is a failure, which is what the old
   `if-no-files-found: error` enforced.

Like the old matrix, a failing environment does not stop the others; the script
prints a per-environment table and exits non-zero if anything failed.

### Two suites are expected red

```
test_daly_d2_decoder     fixtures disagree with the decoder's own length constants
test_ks_bms_decoder      a one-byte SOH-threshold disagreement
```

Neither is a JK-BMS path and neither ships. `run-checks.sh` fails only on
`BUILD-FAIL` / `FAIL` lines that are **not** one of these two, and it names both
of them on every run, so a red run is never mistaken for a fresh regression.
A current green run is:

```
passed 11   build-fail 0   test-fail 2   skipped 0
```

Anything other than those two failing means something regressed.

---

## 2. Prepare the release

1. Set the version in `include/FirmwareVersion.h`. `release.sh` reads it and
   refuses to run if the argument does not match it, so there is no way to tag a
   version that was never built.
2. Run `./scripts/run-checks.sh` and get a green table.
3. Push `main` and tag it `firmware-v<version>`.
4. Read the release notes and the changelog before tagging. See
   `docs/release-notes-template.md`.

```bash
git tag firmware-v<version>
git push origin main firmware-v<version>
```

`release.sh` checks that a `firmware-v*` tag on `HEAD` matches the source
version, and refuses to create a GitHub release from a tag that points at a
different commit than `HEAD`.

---

## 3. Secrets the release script requires

All four must be exported in the shell that runs `release.sh`.

| Variable | Required | Where it comes from |
| --- | --- | --- |
| `OTA_SIGNING_PRIVATE_KEY_B64` | yes, for any OTA target | base64 of the ECDSA P-256 private PEM, `base64 -w0 ota-signing-private.pem`. Keep offline/escrowed. |
| `CLOUDFLARE_API_TOKEN` | yes | Cloudflare API token with **Account → Workers R2 Storage:Edit** and **D1:Edit**. Roll at <https://dash.cloudflare.com/profile/api-tokens>. |
| `CLOUDFLARE_ACCOUNT_ID` | yes | `9c686ab673caa0f69af5bee930392670`. It is **not** optional and **not** defaulted — see the trap below. |
| `GH_TOKEN` (or an authenticated `gh`) | yes | GitHub token with `contents:write` on this repository. |
| `OTA_SIGNING_KEY_ID` | no | Defaults to `jkbmsr-ota-p256-20260705`. Set it when rotating the key. |
| `OTA_SIGNATURE_ALGORITHM` | no | Defaults to `ecdsa-p256-sha256`. |
| `RELEASED_AT` | no | Pins the release timestamp. Set it when re-running a partially published release so regenerated files are comparable. |

The **private** OTA signing key is deliberately not in this repository. There
is no default, no generated fallback, and no "unsigned is fine" path: if
`OTA_SIGNING_PRIVATE_KEY_B64` is unset, `release.sh` stops with an explanation
before it builds anything. The key is never printed, never traced, and the
temporary PEM is shredded on exit including on failure.

`RELEASES_REPO_PUSH_TOKEN` is **gone**. It existed only to push the public
release artifacts into the separate `jkbmsr/jkbmsr-releases` repository. Those
artifacts now live in `releases/` in this repository, so the cross-repo clone
and its token are no longer needed. Nothing to rotate, nothing to revoke.

---

## 4. Release

```bash
cd firmware
./scripts/release.sh <version> --dry-run     # read this first
./scripts/release.sh <version> --yes
```

Useful flags:

| Flag | Effect |
| --- | --- |
| `--dry-run` | print the whole plan, change nothing |
| `--target <name>` | only this gateway target (repeatable) |
| `--skip-build` | reuse the existing `.pio/build/<env>` artifacts (re-publish after a partial failure) |
| `--no-publish` | build, sign, validate and stage only; no R2, D1, GitHub, or commit |
| `--no-push` | publish and commit, but leave the commit local |
| `--verify-cdn` | HTTP-read every published artifact from cdn.jkbmsr.com and compare SHA-256 |

The script publishes, in this order, and only for targets that have an OTA
channel (`esp8266-uart-lite` does not — USB reflash only):

1. **Build** each target, verify the release image really is the application
   (boot banner present, test runner absent), SHA-256 it, and collect
   `bootloader.bin` / `partitions.bin` / `boot_app0.bin`.
2. **Sign** the OTA metadata, then gate it with
   `python3 scripts/validate-ota-release-bundle.py`.
3. **Upload to R2** — `npx wrangler r2 object put ... --remote`.
4. **Update D1** — the `firmware` row for that target, superseding the previous
   `is_latest` for the same target.
5. **Create the GitHub release** for `firmware-v<version>`, with
   target-scoped asset names.
6. **Commit the public mirror** in `releases/`, validate the index, and push.

A pre-flight runs first and reports **every** problem it finds at once, rather
than stopping at the first.

---

## 5. Then, by hand: publish the CDN and verify

The public artifacts are committed to `releases/` in this repository, but that
directory is only *served* once it is deployed. That deploy is a separate,
deliberate step:

```bash
# deploy releases/ to Cloudflare Pages project 'jkbmsr-releases' -> cdn.jkbmsr.com
```

**Project names are load-bearing.**

- `jkbmsr-releases` → `cdn.jkbmsr.com` — this is the one for firmware artifacts.
- `jkbmsr-docs` → `docs.jkbmsr.com`.
- The apex `jkbmsr.com` is **Pages project `jkbmsr-marketing`** (the Astro
  marketing site since 2026-09-27; WordPress deliberately still runs behind the
  tunnel for a crawl cycle only). This release deploy targets `jkbmsr-releases`
  only. The 2026-09-12 outage was a static export deployed into `jkbmsr-web`,
  the product app — never target that, or the apex, from here.

Then verify what a client would actually download:

```bash
./scripts/release.sh <version> --no-publish --verify-cdn --yes
```

This performs a real unauthenticated HTTP read of every
`https://cdn.jkbmsr.com/firmware/<target>/v<version>/firmware.bin` and compares
the SHA-256 against the build. It is deliberately **not** a
`wrangler r2 object get` readback, because a readback through the wrong account
reports a false match.

Finally, check the OTA path end to end against the live API:

```bash
./scripts/test-production-ota.sh
```

---

## Traps encoded in these scripts

Read these before changing anything. Each one cost real time.

**`CLOUDFLARE_ACCOUNT_ID` is not optional.** The API token can see both the
pre-migration Cloudflare account and the current one, and *both* have an R2
bucket named `jkbmsr-firmware`. With only the token exported,
`wrangler r2 object put --remote` wrote to the **old** account, and a
`wrangler r2 object get --remote` readback — also against the old account —
reported a perfect `MATCH` while the live API kept serving the old object.
`release.sh` requires the variable, asserts it equals
`9c686ab673caa0f69af5bee930392670`, and verifies every uploaded object through
the R2 REST API, whose URL contains the account id and therefore cannot answer
from the wrong account.

**`--remote` is not optional.** Recent `wrangler` defaults
`r2 object put`/`get` to *local* storage, so an upload without `--remote`
succeeds while publishing nothing at all.

**`wrangler r2 object list` does not exist.** Enumerate R2 through the REST
API (`/accounts/<id>/r2/buckets/<bucket>/objects`), which also makes the
account id explicit in the URL.

**PlatformIO is pinned to 6.1.19.** Do not relax it.

**The published OTA public key must not be gitignored.** The repository root
`.gitignore` has a blanket `*.pem` rule, added to keep private keys out of a
public tree. That rule currently matches **both**
`firmware/docs/ota-signing-public-key.pem` and
`releases/ota/keys/public/<key-id>.pem`, so neither is committed and a fresh
clone has no verification key at all. In the old split-repo layout the key was
copied into `jkbmsr-releases`, whose `.gitignore` had no such rule, so it
committed fine. Add negations for the *published* public keys and re-add them:

```gitignore
!releases/ota/keys/public/*.pem
!firmware/docs/ota-signing-public-key.pem
```

Do not `git add -f` a key into a tree that says every `.pem` is a secret — the
negation is the fix, the force-add hides it. `release.sh` checks for this and
stops the release, because a release with no published verification key is a
release no client can verify.

**The signing key must match the published public key.** Devices verify against
the key embedded in their own firmware image, not against anything served here,
so signing with a rotated-but-unpublished key produces metadata that no device
can accept. `release.sh` derives the public key from the supplied private key
and refuses to continue unless it matches the published one.

**A re-run re-signs.** ECDSA is randomised by design, so regenerating
`firmware-metadata.json` for an already-published version produces a new, equally
valid signature rather than a byte-identical file. Do not expect "no public
release changes to commit" from a re-run.

**`update_release_index.py` must run with `releases/` as the working
directory.** It writes the relative path `firmware/releases.json`. The script
itself lives in `firmware/scripts/`; `releases/scripts/` contains only
`validate_release_index.py`.

**`generate-flash-manifest.py` is read from `firmware/scripts/`.** It resolves
`hardware-targets.json` relative to its own parent, so the copy in
`firmware/scripts/` reads `firmware/hardware-targets.json` and the one copied
into `releases/firmware/` stays in sync automatically.

---

## Why the public mirror is a commit, not a second clone

The old workflow's last step cloned `jkbmsr/jkbmsr-releases` and pushed the
public artifacts there under a `RELEASES_REPO_PUSH_TOKEN`. Those artifacts now
live in `releases/` in this repository, so the cross-repo clone and that token
are gone: the same files are written to `releases/` and committed to the remote
the source is already on. No second repository to authenticate to, no second
remote to push.

That step also carried a long comment about a real defect. An earlier version of
its retry loop re-synced only `firmware/releases.json` before regenerating it,
leaving every *other* target's `firmware/<other-target>/latest.json` exactly as
they were at that leg's original clone — stale, or missing entirely if a
concurrent leg pushed in between. `validate_release_index.py` cross-checks
`releases.json` against every target's own `latest.json`, so a stale or missing
file failed validation even though the push itself would have succeeded. The
fix at the time was `git reset --hard origin/main` before each attempt.

Three things preserve that intent here, and none of them is `reset --hard`:

1. All seven targets are published by one process in one pass, so there is no
   longer a concurrent second writer whose push can be missed.
2. `releases/` must be clean before the loop starts *and* is re-checked at the
   top of every attempt, and every generated file is rewritten from scratch on
   every attempt — target-scoped files included.
3. `releases/scripts/validate_release_index.py` runs on every attempt and still
   cross-checks `releases.json` against every target's `latest.json`, so a stale
   or missing file fails the gate instead of being published.

`git reset --hard` is deliberately not used on a retry. This is the operator's
working tree, not a throwaway clone, and discarding uncommitted work to win a
push race is not a trade worth making. On a genuine non-fast-forward the script
stops and prints the exact commands to run instead.
