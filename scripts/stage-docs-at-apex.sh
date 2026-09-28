#!/usr/bin/env bash
#
# stage-docs-at-apex.sh — build the documentation site and place it inside the
# marketing site's Cloudflare Pages output, so jkbmsr.com/docs/ serves it.
#
# IT PUBLISHES NOTHING. There is no Cloudflare write anywhere in this script or
# in the node program it calls. The publish step is a separate, explicitly-typed
# command, printed at the end of a successful run and written out in full in
# DEPLOY.md. Nothing here needs credentials.
#
# WHY THIS IS A SCRIPT AND NOT A LINE IN DEPLOY.md
#   The marketing build EMPTIES dist/client on every run. So the order is
#   load-bearing and completely invisible: stage first and the output is
#   deleted; stage second and it ships. A rule a human has to remember is the
#   same shape of mistake as the four docs icons that sat in
#   docs/docs/.vitepress/public/ — a directory VitePress never reads — and
#   404'd for the site's entire life behind a build that reported success and a
#   site that reported 200 on every page.
#
#   The other thing a script buys is that the VERIFICATION runs every time.
#   Every check in stage-docs.mjs is a negative result — 0 escapes, 0
#   collisions, 0 changed, 0 unresolvable — and a negative result from a check
#   that cannot fail reads as assurance. scripts/stage-docs.test.mjs exists to
#   show each of those guards failing on input that should make it fail.
#
# ORDER, and why each step is where it is:
#   1. astro build          (marketing repo)  empties dist/client
#   2. THIS SCRIPT          (docs repo)       stages into dist/client/docs
#   3. astro preview        (marketing repo)  browse http://localhost:4321/docs/
#   4. strip wrangler.json  (marketing repo)  Pages rejects that shape
#   5. wrangler pages deploy                 the only step that publishes
#
#   Steps 3 and 4 are not this script's to do, and the order between them is not
#   interchangeable: astro preview needs dist/client/wrangler.json to know a
#   build exists, and Pages rejects the file. So preview strictly before the
#   strip.
#
# Usage:
#   scripts/stage-docs-at-apex.sh                 # build + stage + verify
#   scripts/stage-docs-at-apex.sh --check-only    # verify a staged tree, write nothing
#   scripts/stage-docs-at-apex.sh --skip-install  # assume docs/node_modules is current
#   scripts/stage-docs-at-apex.sh --no-externalise
#   scripts/stage-docs-at-apex.sh --apex-dist DIR # override the marketing build path
#   scripts/stage-docs-at-apex.sh --test          # run stage-docs.test.mjs too
#   -h, --help                                   # this text
#
# Exit status: 0 staged and every assertion held, 1 refused, 2 could not run.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
DOCS_DIR="$REPO_ROOT/docs"
STAGE="$SCRIPT_DIR/stage-docs.mjs"
TEST="$SCRIPT_DIR/stage-docs.test.mjs"

# The marketing site is a SEPARATE repository and a separate checkout. It is not
# vendored here, and it is not fetched here. The path is overridable because a
# hard-coded one is a stale premise waiting to happen.
APEX_DIST="${APEX_DIST:-/home/jkbmsr/jkbmsr-site/dist/client}"

# The sub-path the staged copy will be served at, and therefore the `base` the
# VitePress build must be given. Stated once, here, because it is a property of
# WHERE THE OUTPUT GOES and not of the docs content.
APEX_DOCS_BASE="/docs/"

SKIP_INSTALL=0
CHECK_ONLY=0
NO_EXTERNALISE=0
RUN_TEST=0

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
ok()   { printf '   ok    %s\n' "$*"; }
info() { printf '   ..    %s\n' "$*"; }
die()  { printf '\nstage-docs-at-apex: FAILED — %s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --check-only)    CHECK_ONLY=1; shift ;;
    --skip-install)  SKIP_INSTALL=1; shift ;;
    --no-externalise) NO_EXTERNALISE=1; shift ;;
    --test)          RUN_TEST=1; shift ;;
    --apex-dist)     APEX_DIST="$2"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *)               die "unknown argument: $1 (try --help)" ;;
  esac
done

[ -f "$STAGE" ] || die "stage-docs.mjs not found at $STAGE"
[ -d "$DOCS_DIR" ] || die "docs component not found at $DOCS_DIR"

# ── Preflight, stated as facts rather than assumed ─────────────────────────────
step "inputs"
info "docs repository    $REPO_ROOT"
info "docs build output  $DOCS_DIR/docs/.vitepress/dist"
info "apex Pages output  $APEX_DIST"
if [ -d "$APEX_DIST" ]; then
  ok "apex Pages output exists ($(find "$APEX_DIST" -type f | wc -l | tr -d ' ') files)"
else
  die "apex Pages output not found: $APEX_DIST
       This script stages INTO an existing marketing build; it does not create one.
       Run \`npm run build\` in /home/jkbmsr/jkbmsr-site first.
       Staging before astro build would be silently deleted by it."
fi
if [ -f "$APEX_DIST/wrangler.json" ] || [ -d "$APEX_DIST/.wrangler" ]; then
  info "dist/client/wrangler.json or .wrangler/ is present — the Astro Cloudflare adapter emitted them."
  info "They must be stripped AFTER astro preview and BEFORE wrangler pages deploy; Pages rejects that shape."
fi

# DOCS_BASE is what makes the apex copy live at /docs/. It is set HERE, not in the
# VitePress config, because the same build also has to work at the ROOT for
# docs.jkbmsr.com — see the long note above `const BASE` in
# docs/docs/.vitepress/config.ts.
#
# Asserted rather than merely exported, because getting it wrong produces a build
# that SUCCEEDS and a site that is broken; stage-docs.mjs would then refuse on
# ~1,700 escaping references, and this makes the cause one line instead. A value
# already in the environment is honoured if it matches and refused if it does not,
# because silently overwriting what the caller set is how a script becomes
# something you have to read before trusting.
if [ -n "${DOCS_BASE:-}" ] && [ "$DOCS_BASE" != "$APEX_DOCS_BASE" ]; then
  die "DOCS_BASE is set to '$DOCS_BASE' but this script stages into '$APEX_DOCS_BASE'.
       Unset it, or set it to '$APEX_DOCS_BASE'. Refusing to overwrite it silently."
fi
ok "DOCS_BASE=$APEX_DOCS_BASE — the apex copy must live under /docs/; the subdomain build uses /"
info "The subdomain build (scripts/deploy-docs.sh) deliberately uses base '/', so docs.jkbmsr.com is unaffected."

# ── Build the docs ────────────────────────────────────────────────────────────
if [ "$CHECK_ONLY" -eq 0 ]; then
  step "install dependencies"
  if [ "$SKIP_INSTALL" -eq 1 ]; then
    info "--skip-install: using the existing docs/node_modules"
    [ -d "$DOCS_DIR/node_modules" ] || die "--skip-install given but docs/node_modules does not exist"
  else
    ( cd "$DOCS_DIR" && npm ci ) || die "npm ci failed — the docs cannot be built, and reasoning about what the build would produce is not a substitute"
    ok "npm ci"
  fi

  step "build the docs site (npm run docs:build)"
  # VitePress dies on a dead internal link, an unresolvable sidebar entry or a
  # failed SSR render. It does NOT fail on a wrong `base`, on a missing static
  # asset, or on a policy conflict with the apex's headers — those are
  # stage-docs.mjs's job, which is why both halves exist.
  ( cd "$DOCS_DIR" && DOCS_BASE="$APEX_DOCS_BASE" npm run docs:build ) || die "npm run docs:build failed"
  [ -d "$DOCS_DIR/docs/.vitepress/dist" ] || die "the build reported success but produced no output directory"
  ok "built $(find "$DOCS_DIR/docs/.vitepress/dist" -name '*.html' | wc -l | tr -d ' ') HTML pages"
else
  info "--check-only: not rebuilding the docs, so this verifies what is already staged"
fi

# ── Stage and verify ──────────────────────────────────────────────────────────
step "stage into the apex output and verify"
[ "$NO_EXTERNALISE" -eq 1 ] && set -- --no-externalise || set --
node "$STAGE" --apex-dist "$APEX_DIST" "$@"
stage_rc=$?

# ── Optional: prove the guards can fail ───────────────────────────────────────
if [ "$RUN_TEST" -eq 1 ]; then
  step "stage-docs.test.mjs — every guard, shown failing on input that should make it fail"
  node "$TEST" || die "a guard did not behave as specified, so the run above proves less than it appears to"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
step "summary"
say "   apex Pages output  $APEX_DIST"
say "   staged docs        $APEX_DIST/docs"
say "   published          no"
say ""
say "   Next, in this order. Steps 3 and 4 are NOT interchangeable:"
say "     cd /home/jkbmsr/jkbmsr-site"
say "     npm run preview            # browse http://localhost:4321/docs/  (binds [::1] only)"
say "     # stop preview, and only then strip:"
say "     rm -f  dist/client/wrangler.json && rm -rf dist/client/.wrangler"
    # There are TWO .wrangler directories and the deploy fails if either survives.
  # `dist/client/.wrangler` is the Astro adapter's; `./.wrangler` is written by
  # wrangler itself at the cwd you invoke it from, and it holds a
  # `deploy/config.json` naming `dist/client/wrangler.json` as the config path.
  # Deleting only the former leaves that pointer dangling and the deploy dies with
  # "There is a deploy configuration at .wrangler/deploy/config.json" — which is
  # exactly the confusing half of an otherwise obvious error. Measured 2026-09-28.

say "     npx wrangler@4.118.0 pages deploy dist/client \\"
say "       --project-name jkbmsr-marketing --branch main"
say ""
say "   wrangler is PINNED. \`npx wrangler\` floats to the newest published"
say "   version, and 4.141.0 broke a run on 2026-09-26 when 4.118.0 was known-good."
exit "$stage_rc"
