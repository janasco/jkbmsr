# Contributing

Thanks for looking at this. Two rules below are not stylistic preferences — one
of them is a safety requirement.

## 1. Never guess a protocol

This project reads battery-management hardware. If a frame format, checksum,
register address, byte offset, or scaling factor is wrong, the result is not a
parse error — it is a plausible-looking wrong number about a battery, which
someone might act on.

So any change to protocol handling must be:

- **Verified against a real reference implementation.** The community projects
  under `syssi/esphome-*-bms` are what the existing decoders were derived from.
  Cite which one, and which part of it.
- **Or verified against a captured frame from real hardware**, ideally with the
  capture committed as a regression fixture.
- **Never inferred from forum posts, marketing copy, or a plausible pattern.**

If you cannot point at a source, do not write the parser. Open a discussion
instead — an unimplemented decoder is fine, a wrong one is not.

When you add a decoder, add a test that fails without your change. A decoder
with no test is not finished.

## 2. Never commit secrets

The following are excluded from this repository and must be supplied locally:

| What | Where it comes from |
| :--- | :--- |
| Android upload/signing keys (`*.jks`, `*.keystore`, `key.properties`) | Play Console → Setup → App integrity |
| `google-services.json` | Firebase console, downloaded per-app |
| `.env`, `.env.local`, `scripts/.env.local` | Local environment |
| API tokens, webhook secrets, JWT secrets | Provider dashboards |
| Play in-app product / subscription secrets | Play Console |

The launcher icons and other artwork **are** generated from
`brand/`-equivalent tooling and are committed; the signing material is not. If
you add a build step that needs a secret, wire it to an environment variable and
fail loudly if it is absent — do not add a default.

## Workflow

- Branch from `main`, one topic per branch.
- Conventional commit prefixes: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`,
  `chore:`. `ci:` is deliberately not in the list: nothing runs on a commit or
  on a pull request here, so a change labelled `ci:` is a change to something
  that does not exist.
- Author commits as `janasco <janasco@duck.com>`.
- **There is no hosted CI.** No GitHub Actions, no runners, no automatic
  checks. If you do not run the checks, they have not been run, and no reviewer
  will see anything that tells you otherwise. Run them before you open a pull
  request:

  ```bash
  # everything
  scripts/check-all.sh --run

  # just the component you touched
  scripts/check-all.sh --run --only apps/pro
  ```

  It covers `flutter analyze && flutter test` for both apps, the native
  ASan/UBSan host suites plus the device-profile and hardware-target
  validators for the firmware, `npm run docs:build` for the docs site, and
  `python3 scripts/validate_release_index.py` for the release index. `SKIP` in
  its table is not `PASS`; add `--strict` when you are the last person before a
  merge and want an unrun component to be a failure.

  Run with no arguments to print the plan without executing anything.
- Publishing is manual too. `scripts/deploy-docs.sh` and
  `scripts/deploy-releases.sh` build and publish the documentation site and the
  release CDN; with no arguments they only print what they would do and publish
  nothing. The operator procedure, the host map, and the traps that have cost
  this project real time are in [DEPLOY.md](DEPLOY.md). If you add a deploy
  target, add it to the host map there, and verify it with a real HTTP read of
  the public URL plus a hash comparison — never with a `wrangler ... get`
  readback, which can read local storage or the wrong Cloudflare account and
  still report a match.
- Do not rewrite published history.

## Reporting a safety issue

If you find a bug that could cause someone to act on a wrong battery reading, or
a vulnerability, please report it privately rather than in a public issue. See
`support/README.md` for the current contact route.

## Compatibility claims

This project supports JK-BMS only. Do not add compatibility claims for other
vendors, and do not add a vendor to the public surface (README, docs, store
listing, app UI) without a hardware-validated decoder behind it.
