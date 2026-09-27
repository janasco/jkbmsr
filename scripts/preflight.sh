#!/usr/bin/env bash
#
# preflight.sh — assert the environment is safe BEFORE anything is published.
#
# This repository has no hosted CI. Every Cloudflare deploy is a person running
# a script on a laptop or on the build host, which means there is no runner
# whose secrets are injected for you and no second pair of eyes. This script is
# that safety net, and it is deliberately strict: it is cheaper to fail here
# than to publish firmware to the wrong Cloudflare account.
#
# The three things that have actually gone wrong on this platform:
#
#   1. A Pages deploy aimed at the apex `jkbmsr.com`. The apex is WordPress.
#      Deploying a Pages build there is what caused the 2026-09-12 outage.
#      A Pages project name is load-bearing: do not "fix" one of these to
#      something that sounds more correct.
#   2. `CLOUDFLARE_ACCOUNT_ID` unset. The API token can see BOTH the old and
#      the new Cloudflare account, and both accounts have same-named buckets
#      and same-named Pages projects. With the account id missing, wrangler
#      picks an account on its own — and wrote to the wrong one in practice.
#      A `wrangler r2 object get` readback from that same wrong account then
#      reported a false MATCH while the live API kept serving the old object.
#      So the account id is mandatory, and it is checked against a literal.
#   3. `wrangler r2 object put/get` silently defaulting to LOCAL storage in
#      recent wrangler versions. Every remote object operation needs `--remote`.
#      (This script never performs object operations; it only reports the CLI
#      surface so the trap stays visible at the top of every deploy.)
#
# Usage:
#   scripts/preflight.sh --project jkbmsr-docs            # enforce, non-zero on failure
#   scripts/preflight.sh --project jkbmsr-releases --report   # print, always exit 0
#
# Options:
#   --project NAME   Pages project this run is about to deploy to (required).
#   --report         Evaluate and print every check but never fail. Used by the
#                    deploy scripts in dry-run and build-only mode so those
#                    modes stay usable without Cloudflare credentials.
#   --skip-wrangler  Skip the wrangler CLI probe (version + subcommand surface).
#   -h, --help       This text.
#
# Environment:
#   CLOUDFLARE_API_TOKEN   required, non-empty.
#   CLOUDFLARE_ACCOUNT_ID  required, must equal EXPECTED_ACCOUNT_ID below.
#   WRANGLER_CMD           override the wrangler invocation (default "npx wrangler").
#                          Pin it for a reproducible deploy, e.g.
#                          WRANGLER_CMD="npx wrangler@4.118.0".
#
# Exit status: 0 all checks passed (or --report), 1 a check failed, 2 usage error.

set -euo pipefail

# The account every manual deploy must target. This is the post-migration
# account; the pre-migration one still answers to the same token, which is
# exactly why this is checked as a literal rather than trusted from the
# environment. Cloudflare zone for jkbmsr.com: 98bf528fbb8bcb1722ae080ecd7f05d0.
EXPECTED_ACCOUNT_ID="9c686ab673caa0f69af5bee930392670"

# The apex. WordPress serves it. It must never be a Pages deploy target.
APEX="jkbmsr.com"

# Every Pages project on the platform. A deploy target outside this list is a
# mistake, not a new feature.
KNOWN_PAGES_PROJECTS="jkbmsr-admin jkbmsr-docs jkbmsr-releases jkbmsr-web"

# `wrangler pages deploy --project-name ... --branch ...` needs wrangler 3+;
# require 4 to keep the CLI surface stable across the flags used below.
MIN_WRANGLER_MAJOR=4

PROJECT=""
REPORT=0
CHECK_WRANGLER=1
FAILURES=0

say()  { printf '%s\n' "$*"; }
ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  WARN  %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }
die()  { printf 'preflight: %s\n' "$*" >&2; exit 2; }

usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; }

# The host map, printed on every failure. A wrong deploy target is obvious once
# you can see that the apex is WordPress and each subdomain has exactly one home.
print_host_map() {
  cat >&2 <<'HOSTMAP'

  Host map — the apex is WordPress; every subdomain below has exactly one home:
    jkbmsr.com        = WordPress (jkbmsr-wp)   NEVER a Pages deploy target
    www.jkbmsr.com    = WordPress (jkbmsr-wp)   NEVER a Pages deploy target
    web.jkbmsr.com    = Pages project jkbmsr-web
    docs.jkbmsr.com   = Pages project jkbmsr-docs
    cdn.jkbmsr.com    = Pages project jkbmsr-releases
    api.jkbmsr.com    = Cloudflare Worker (jkbmsr-api) — not Pages at all
    admin.jkbmsr.com  = Pages project jkbmsr-admin

  Deploying a Pages build to the apex is what caused the 2026-09-12 outage.
HOSTMAP
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)   [ $# -ge 2 ] || die "--project needs a value"; PROJECT="$2"; shift 2 ;;
    --project=*) PROJECT="${1#*=}"; shift ;;
    --report)    REPORT=1; shift ;;
    --skip-wrangler) CHECK_WRANGLER=0; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           die "unknown argument: $1 (try --help)" ;;
  esac
done

[ -n "$PROJECT" ] || die "--project is required (try --help)"

say "preflight: target Pages project = $PROJECT"
say "----------------------------------------------------------------------"

# ---------------------------------------------------------------------------
# 1. Target project
# ---------------------------------------------------------------------------
# The apex is refused outright, before anything else, so a mistyped target can
# never reach the network.
if [ "$PROJECT" = "$APEX" ] || [ "$PROJECT" = "www.$APEX" ]; then
  bad "refusing to deploy to the apex '$PROJECT' — the apex is WordPress."
  print_host_map
  say "" >&2
  say "preflight: FAILED (${FAILURES} check(s))" >&2
  exit 1
fi

case " $KNOWN_PAGES_PROJECTS " in
  *" $PROJECT "*) ok "target '$PROJECT' is a known Pages project" ;;
  *)
    # No inline host map here: every failure prints it once, at the end.
    bad "unknown Pages project '$PROJECT' (known: $KNOWN_PAGES_PROJECTS)"
    ;;
esac

# ---------------------------------------------------------------------------
# 2. Cloudflare API token
# ---------------------------------------------------------------------------
if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  bad "CLOUDFLARE_API_TOKEN is not set (or is empty)."
  say "" >&2
  cat >&2 <<'MSG'
  Source: Cloudflare dashboard -> Profile -> API Tokens.
  Needs:  Account > Cloudflare Pages:Edit (Workers R2 Storage:Edit and D1:Edit
          as well if you also publish firmware from the same shell).
  Never put it in a committed file. On the build host a working copy lives in
  the private repository at `jkbmsr-private/backend/.env` (gitignored, mode
  0600, owned by the user you are logged in as). Source it, or export the
  variables; do not copy the file. See DEPLOY.md.
MSG
elif case "$CLOUDFLARE_API_TOKEN" in ghp_*|gho_*|ghu_*|ghs_*|ghr_*|github_pat_*) true ;; *) false ;; esac; then
  # Not a wrong-account bug, but the same class of mistake: a GitHub token in a
  # Cloudflare variable fails at the API with an unhelpful message.
  bad "CLOUDFLARE_API_TOKEN looks like a GitHub token, not a Cloudflare API token."
else
  ok "CLOUDFLARE_API_TOKEN is set (${#CLOUDFLARE_API_TOKEN} chars, value not shown)"
fi

# ---------------------------------------------------------------------------
# 3. Cloudflare account id — the one that must be exactly right
# ---------------------------------------------------------------------------
if [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
  bad "CLOUDFLARE_ACCOUNT_ID is not set. This is not optional and not paranoia."
  cat >&2 <<MSG

  The API token above can see BOTH the pre-migration and the post-migration
  Cloudflare account, and both accounts have same-named buckets and Pages
  projects. With no account id in the environment, wrangler picks one itself —
  and on this platform that was the OLD account, silently. A readback from the
  same wrong account then reported a false match while the live API kept
  serving the old object, which is what turned a misroute into a failed
  publish.

  Expected value: $EXPECTED_ACCOUNT_ID
  Set it explicitly, e.g.

      export CLOUDFLARE_ACCOUNT_ID=$EXPECTED_ACCOUNT_ID
      export CLOUDFLARE_API_TOKEN=...   # never committed, see DEPLOY.md
MSG
elif [ "$CLOUDFLARE_ACCOUNT_ID" != "$EXPECTED_ACCOUNT_ID" ]; then
  bad "CLOUDFLARE_ACCOUNT_ID is $CLOUDFLARE_ACCOUNT_ID, expected $EXPECTED_ACCOUNT_ID."
  say "" >&2
  cat >&2 <<'MSG'
  Refusing to continue. If you genuinely need to deploy to a different account,
  change EXPECTED_ACCOUNT_ID in scripts/preflight.sh deliberately, and read the
  host map below first — the two accounts share every resource name, so a
  mismatched id is indistinguishable from a correct one until something breaks.
MSG
else
  ok "CLOUDFLARE_ACCOUNT_ID is $EXPECTED_ACCOUNT_ID (the account every deploy must target)"
fi

# ---------------------------------------------------------------------------
# 4. Wrangler CLI surface
# ---------------------------------------------------------------------------
if [ "$CHECK_WRANGLER" -eq 1 ]; then
  read -r -a WRANGLER <<<"${WRANGLER_CMD:-npx wrangler}"

  version_output=$("${WRANGLER[@]}" --version 2>&1) || version_output=""
  wrangler_version=$(printf '%s\n' "$version_output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)

  if [ -z "$wrangler_version" ]; then
    bad "could not determine a wrangler version from '${WRANGLER[*]} --version'."
    say "        output: ${version_output:-<empty>}" >&2
    say "        the first run downloads wrangler into the npx cache; check the network" >&2
  else
    wrangler_major=${wrangler_version%%.*}
    if [ "$wrangler_major" -lt "$MIN_WRANGLER_MAJOR" ]; then
      bad "wrangler $wrangler_version is older than the required $MIN_WRANGLER_MAJOR.x."
    else
      ok "wrangler $wrangler_version  (${WRANGLER[*]})"
    fi

    # Confirm the exact subcommands and flags these deploy scripts depend on,
    # rather than assuming the CLI still looks like it did when they were
    # written. `--project-name` and `--branch` are what keep a deploy on
    # jkbmsr-docs / jkbmsr-releases and on the main branch.
    pages_help=$("${WRANGLER[@]}" pages deploy --help 2>&1 || true)
    for flag in --project-name --branch; do
      if printf '%s\n' "$pages_help" | grep -q -- "$flag"; then
        ok "wrangler pages deploy supports $flag"
      else
        bad "wrangler pages deploy does not advertise $flag — do not guess the replacement."
      fi
    done

    # The documented R2 traps, re-confirmed against the installed CLI so they
    # cannot quietly stop being true:
    #   * `r2 object list` does not exist. Enumerate through the REST API
    #     (GET /accounts/<id>/r2/buckets/<bucket>/objects), which also makes
    #     the account explicit in the URL so you know which account answered.
    #   * `r2 object put` / `get` default to LOCAL storage. Always --remote.
    r2_help=$("${WRANGLER[@]}" r2 object --help 2>&1 || true)
    if printf '%s\n' "$r2_help" | grep -qE '^  wrangler r2 object list'; then
      warn "this wrangler now has 'r2 object list'; the known-good enumeration path is the REST API"
    else
      ok "'wrangler r2 object list' does not exist in $wrangler_version (as expected)"
    fi
    if printf '%s\n' "$r2_help" | grep -q 'wrangler r2 object put' \
       && printf '%s\n' "$r2_help" | grep -q 'wrangler r2 object get'; then
      ok "'r2 object put' and 'r2 object get' are present — pass --remote to both (local is the default)"
    else
      bad "'r2 object put'/'r2 object get' are missing from this wrangler; re-check any firmware publish path"
    fi
  fi
else
  warn "wrangler probe skipped (--skip-wrangler)"
fi

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
say "----------------------------------------------------------------------"
if [ "$FAILURES" -eq 0 ]; then
  ok "preflight passed for $PROJECT"
  exit 0
fi

if [ "$REPORT" -eq 1 ]; then
  warn "preflight found $FAILURES problem(s) — reported only because --report was given."
  say "         A real deploy would refuse to run until these are fixed."
  exit 0
fi

say "" >&2
print_host_map
say "" >&2
say "preflight: FAILED (${FAILURES} check(s)) — nothing was published." >&2
exit 1
