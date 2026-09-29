#!/usr/bin/env bash
#
# deploy-docs.sh — build the documentation site and publish it to Cloudflare
# Pages. Replaces the two GitHub Actions workflows that used to do this:
#
#   docs/.github/workflows/docs.yml   (validate)   -> steps 1-2 below
#   docs/.github/workflows/pages.yml  (build)      -> steps 3-5 below
#                                  (deploy)       -> step 6 below
#
# Those were two jobs joined by an uploaded artifact (`jkbmsr-docs-dist`). With
# no Actions there is no artifact hand-off, so this is one script that builds
# and deploys in sequence — and the build half is still runnable on its own with
# --build-only.
#
# The Pages project name `jkbmsr-docs` and the branch `main` are load-bearing.
# Do not rename them. docs.jkbmsr.com points at this project; deploying
# anywhere else publishes nothing, and deploying to the apex jkbmsr.com is what
# caused the 2026-09-12 outage. See DEPLOY.md.
#
# RETIRED SUBDOMAIN, 2026-09-29: docs.jkbmsr.com is no longer a browsable copy.
# A Worker route (jkbmsr-docs-redirect) 301s it to jkbmsr.com/docs/, which is a
# DIFFERENT build on a DIFFERENT Pages project. This script still publishes this
# project because it is the custom-domain origin and the one-command rollback,
# but it verifies the readback against the PROJECT's own hostname — see the note
# on VERIFY_URL below. See ops/deploys/jkbmsr-docs-redirect.md.
#
# Usage:
#   scripts/deploy-docs.sh                  # dry run: validate + print the plan
#   scripts/deploy-docs.sh --build-only     # validate + build, publish nothing
#   scripts/deploy-docs.sh --deploy         # validate + build + publish
#
# Options:
#   --build-only     Stop after the build. No credentials needed.
#   --deploy         Publish. This is the only flag that touches Cloudflare.
#   --dry-run        Explicit spelling of the no-argument default.
#   --skip-install   Do not run `npm ci`; assume docs/node_modules is current.
#   --no-verify      Skip the post-deploy HTTP read + hash comparison.
#   -h, --help       This text.
#
# Environment (publish only): CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID.
# scripts/preflight.sh checks both, plus the account id against a literal,
# before anything is uploaded.
#
# Exit status: 0 success, 1 a step failed.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
DOCS_DIR="$REPO_ROOT/docs"
PREFLIGHT="$SCRIPT_DIR/preflight.sh"
VERIFY="$SCRIPT_DIR/verify-publish.py"

# Load-bearing. See the header.
PAGES_PROJECT="jkbmsr-docs"
PAGES_BRANCH="main"
PUBLIC_URL="https://docs.jkbmsr.com"
# The readback target is the PROJECT's own hostname, not the custom domain, and
# the reason is a 2026-09-29 state change: docs.jkbmsr.com is retired as a
# browsable copy and 301s to jkbmsr.com/docs/, which is a DIFFERENT build
# (base /docs/) on a DIFFERENT Pages project. Following that redirect and hashing
# the result against this project's root-based output would fail on a perfectly
# healthy deploy — a verification that measures the wrong thing. The
# `<project>.pages.dev` hostname serves THIS deployment.
VERIFY_URL="https://jkbmsr-docs.pages.dev"

# The VitePress source directory inside the component is itself called `docs`,
# so the doubled path below is correct, not a typo. The original workflow ran
# with working-directory set to the docs component, which made its `docs/...`
# paths resolve to exactly these files.
VITEPRESS_SRC="$DOCS_DIR/docs"
VITEPRESS_OUT="$VITEPRESS_SRC/.vitepress/dist"

# Where the deploy step's `dist` used to come from. The old pipeline uploaded
# the build output as an artifact and the deploy job unpacked it here, so
# `docs/dist` is the same directory — it just gets filled by `cp` now.
DEPLOY_DIST="$DOCS_DIR/dist"

MODE="dry-run"
SKIP_INSTALL=0
NO_VERIFY=0

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
ok()   { printf '   ok    %s\n' "$*"; }
warn() { printf '   WARN  %s\n' "$*"; }
info() { printf '   ..    %s\n' "$*"; }
die()  { printf '\ndeploy-docs: FAILED — %s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; }

# Both workflows gated the deploy on `if: github.ref == 'refs/heads/main'`, so a
# deploy could only ever happen from main. A script has no such guarantee, so
# check it and say so — as a warning, because a tarball checkout with no git
# directory is a legitimate way to publish a hotfix, and refusing that would be
# trading a real safety property for a cosmetic one.
warn_if_not_main() {
  local branch
  git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 || {
    warn "not a git checkout; cannot confirm this is the main branch"
    return 0
  }
  branch=$(git -C "$REPO_ROOT" symbolic-ref --short HEAD 2>/dev/null || true)
  case "$branch" in
    main|'') : ;;
    *) warn "current branch is '${branch:-detached HEAD}', not main." ;;
  esac
  local dirty
  dirty=$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null | head -5 || true)
  [ -z "$dirty" ] || warn "working tree has uncommitted changes; you are publishing what is on disk, not what is committed:"
  [ -z "$dirty" ] || printf '%s\n' "$dirty" | sed 's/^/          /'
  return 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --build-only)   MODE="build-only"; shift ;;
    --deploy)       MODE="deploy"; shift ;;
    --dry-run)      MODE="dry-run"; shift ;;
    --skip-install) SKIP_INSTALL=1; shift ;;
    --no-verify)    NO_VERIFY=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *)              die "unknown argument: $1 (try --help)" ;;
  esac
done

case "$MODE" in
  dry-run)    info "mode: dry run — nothing will be published" ;;
  build-only) info "mode: build only — nothing will be published" ;;
  deploy)     info "mode: deploy — this WILL publish to $PAGES_PROJECT/$PAGES_BRANCH" ;;
esac

[ -d "$DOCS_DIR" ] || die "docs component not found at $DOCS_DIR"
[ -x "$PREFLIGHT" ] || die "preflight not found or not executable: $PREFLIGHT"

# ---------------------------------------------------------------------------
# 0. Preflight
# ---------------------------------------------------------------------------
# The credentials are only required to publish. In the non-publishing modes the
# same checks run in --report mode, so the operator sees what a real deploy
# would say without needing Cloudflare access at all.
step "preflight ($PAGES_PROJECT)"
warn_if_not_main
if [ "$MODE" = "deploy" ]; then
  "$PREFLIGHT" --project "$PAGES_PROJECT" \
    || die "preflight refused to continue — see the host map above"
else
  "$PREFLIGHT" --project "$PAGES_PROJECT" --report
fi

# ---------------------------------------------------------------------------
# 1. Verify repository structure
#    (docs.yml, "Verify repository structure")
# ---------------------------------------------------------------------------
step "verify repository structure"
require_file() {
  [ -f "$1" ] || die "missing required file: ${1#$REPO_ROOT/}"
  ok "$(printf '%s' "${1#$REPO_ROOT/}")"
}
require_dir() {
  [ -d "$1" ] || die "missing required directory: ${1#$REPO_ROOT/}"
  ok "$(printf '%s' "${1#$REPO_ROOT/}")"
}

require_file "$DOCS_DIR/README.md"
require_dir  "$VITEPRESS_SRC"
require_file "$VITEPRESS_SRC/index.md"
require_file "$VITEPRESS_SRC/internal/release-process.md"

# ---------------------------------------------------------------------------
# 2. Verify markdown inventory
#    (docs.yml, "Verify markdown inventory")
#
# A floor, not a census: it catches a component whose docs were deleted or
# never merged, not a bad link or a missing page. The real check is step 4 —
# VitePress fails the build on a dead internal link.
# ---------------------------------------------------------------------------
step "verify markdown inventory"
md_count=$(find "$VITEPRESS_SRC" -type f -name '*.md' | wc -l | tr -d ' ')
info "markdown files under docs/docs: $md_count"
if [ "$md_count" -lt 10 ]; then
  die "markdown inventory is $md_count files, expected at least 10"
fi
ok "markdown inventory ($md_count files, minimum 10)"

# ---------------------------------------------------------------------------
# 3-5. Build
#    (pages.yml, "Install dependencies" + "Build docs site" + artifact upload)
# ---------------------------------------------------------------------------
if [ "$MODE" = "dry-run" ]; then
  step "plan: install, build, stage, publish, verify"
  cat <<PLAN
   ..    cd docs && npm ci
   ..    cd docs && npm run docs:build
   ..    rm -rf docs/dist && cp -R docs/docs/.vitepress/dist docs/dist
          (the old pipeline filled this directory by unpacking the
           jkbmsr-docs-dist artifact; Pages' 25 MiB per-file cap and the
           _headers/_redirects files are not involved for docs)
   ..    cd docs && npx wrangler pages deploy dist \\
             --project-name $PAGES_PROJECT --branch $PAGES_BRANCH
   ..    python3 scripts/verify-publish.py --url $VERIFY_URL/index.html \\
             --file docs/dist/index.html
PLAN
else
  step "install dependencies (npm ci)"
  if [ "$SKIP_INSTALL" -eq 1 ]; then
    info "--skip-install: using the existing docs/node_modules"
  else
    ( cd "$DOCS_DIR" && npm ci ) || die "npm ci failed"
    ok "npm ci"
  fi

  step "build docs site (npm run docs:build)"
  # VitePress dies on a dead internal link, an unresolvable sidebar entry or a
  # failed SSR render. That is the substantive check the validate job never got
  # to run, because it only counted files.
  ( cd "$DOCS_DIR" && npm run docs:build ) || die "npm run docs:build failed"
  [ -d "$VITEPRESS_OUT" ] || die "build reported success but $VITEPRESS_OUT does not exist"
  page_count=$(find "$VITEPRESS_OUT" -name '*.html' | wc -l | tr -d ' ')
  [ "$page_count" -gt 0 ] || die "build produced no HTML in $VITEPRESS_OUT"
  ok "built $page_count HTML pages into docs/docs/.vitepress/dist"

  step "verify declared static assets reached the build output"
  # VitePress does not fail a build over a missing static asset, and a
  # `<link rel="icon" href="/favicon.svg">` that resolves to nothing looks
  # exactly like one that works when you are editing the config. That is the
  # whole reason four icon files sat in docs/docs/.vitepress/public/ — a
  # directory the build never reads — for the site's entire life: tracked,
  # committed, referenced by the config, absent from every build, and 404ing in
  # production, behind a green build and a 200 on every page.
  #
  # So assert it. Every root-absolute href in the VitePress config that names a
  # file must exist in the build output. Route links ("/api/index") carry no
  # extension and are skipped on purpose: VitePress renders those as .html
  # pages and already dies on a dead internal link, so re-checking them here
  # would add a second, weaker instrument for a failure mode that cannot happen.
  assets=$(grep -oE '(href|logo): *"/[^"]*\.[A-Za-z0-9]+"' \
             "$VITEPRESS_SRC/.vitepress/config.ts" \
           | grep -oE '"/[^"]*"' | tr -d '"' | sort -u || true)
  asset_count=$(printf '%s\n' "$assets" | grep -c . || true)
  # Guard the guard. A checker that finds nothing to check passes, and "all
  # declared assets are present" printed next to a count of zero is a false
  # reassurance of exactly the kind this script exists to prevent.
  [ "$asset_count" -gt 0 ] \
    || die "extracted 0 asset references from the VitePress config, so the check below could only pass vacuously — treat this as the bug, not as a pass"
  missing=0
  while IFS= read -r asset; do
    [ -n "$asset" ] || continue
    if [ -f "$VITEPRESS_OUT$asset" ]; then
      ok "$(printf '%-30s %9s B' "$asset" "$(wc -c <"$VITEPRESS_OUT$asset" | tr -d ' ')")"
    else
      warn "DECLARED IN CONFIG BUT NOT IN THE BUILD: $asset"
      missing=$((missing + 1))
    fi
  done <<EOF
$assets
EOF
  [ "$missing" -eq 0 ] \
    || die "$missing declared asset(s) are absent from the build output — publishing now would reproduce the 404s this check exists to catch"
  ok "all $asset_count declared asset(s) present in the build output"

  step "stage the deploy directory (docs/dist)"
  # Cleared first on purpose. The old pipeline got a fresh checkout for every
  # run, so `dist` could only ever contain the current build; a local working
  # tree does not, and a stale page left behind here would be published as
  # though it were current.
  rm -rf "$DEPLOY_DIST"
  cp -R "$VITEPRESS_OUT" "$DEPLOY_DIST" || die "could not stage $DEPLOY_DIST"
  staged=$(find "$DEPLOY_DIST" -type f | wc -l | tr -d ' ')
  ok "staged $staged files into docs/dist"
fi

# ---------------------------------------------------------------------------
# 6. Deploy
#    (pages.yml, "Deploy")
# ---------------------------------------------------------------------------
if [ "$MODE" != "deploy" ]; then
  step "deploy: skipped (mode is '$MODE')"
  say "   ..    would run: cd docs && npx wrangler pages deploy dist \\"
  say "   ..                   --project-name $PAGES_PROJECT --branch $PAGES_BRANCH"
else
  step "deploy to Cloudflare Pages"
  # The account id is exported by preflight's contract: it is checked, not
  # assumed. `npx wrangler` here is the same invocation the workflow used.
  ( cd "$DOCS_DIR" && npx wrangler pages deploy dist \
      --project-name "$PAGES_PROJECT" --branch "$PAGES_BRANCH" ) \
    || die "wrangler pages deploy failed — nothing is published unless wrangler said otherwise"
  ok "deployed docs/dist to $PAGES_PROJECT ($PAGES_BRANCH)"
fi

# ---------------------------------------------------------------------------
# 7. Verify
#
# Always a real HTTP read of the public URL plus a hash comparison. Never
# `wrangler ... get`: that reads local storage by default, and with a token
# that can see two accounts it can read the wrong one and still report a match.
# ---------------------------------------------------------------------------
if [ "$MODE" = "deploy" ] && [ "$NO_VERIFY" -eq 0 ]; then
  step "verify the published project ($VERIFY_URL)"
  python3 "$VERIFY" --url "$VERIFY_URL/index.html" --file "$DEPLOY_DIST/index.html" \
    || die "verification failed — the deploy landed but the project hostname does not serve these bytes"
  ok "$VERIFY_URL serves the bytes that were deployed (the public docs.jkbmsr.com is retired and 301s to the apex)"
elif [ "$MODE" = "deploy" ]; then
  warn "--no-verify: skipping the HTTP read. Verify by hand before calling this done."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
step "summary"
say "   mode             $MODE"
say "   pages project    $PAGES_PROJECT   (do not rename)"
say "   branch           $PAGES_BRANCH"
say "   public url       $PUBLIC_URL   (retired as a browsable copy; 301s to https://jkbmsr.com/docs/)"
say "   verify url       $VERIFY_URL   (serves this project's own deployment)"
say "   build output     ${DEPLOY_DIST#$REPO_ROOT/}"
say "   published        $([ "$MODE" = deploy ] && echo yes || echo no)"
say ""
say "   next step: run 'scripts/check-all.sh' before opening a pull request;"
say "   see DEPLOY.md for the full manual procedure and the traps."
exit 0
