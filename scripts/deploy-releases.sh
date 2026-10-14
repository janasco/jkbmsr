#!/usr/bin/env bash
#
# deploy-releases.sh — validate, package and publish the public release CDN.
# Replaces releases/.github/workflows/pages.yml (validate + package, then
# deploy).
#
# That workflow was two jobs joined by an uploaded artifact
# (`jkbmsr-releases-dist`): the build job produced releases/dist and the
# deploy job published it. With no Actions there is no artifact hand-off, so
# this is one script that packages and deploys in sequence, and the packaging
# half is still runnable on its own with --build-only.
#
# The Pages project name `jkbmsr-releases` and the branch `main` are
# load-bearing. Do not rename them. cdn.jkbmsr.com points at this project.
# Never point this deploy at the apex: jkbmsr.com is a *different* Pages
# project (`jkbmsr-marketing`, the Astro marketing site since 2026-09-27).
# The 2026-09-12 outage was a static export deployed into `jkbmsr-web`, the
# product app — so target `jkbmsr-releases` and nothing else. See DEPLOY.md.
#
# FIRMWARE IS NOT PUBLISHED HERE. This host is for the release index, the
# public OTA verification material (ota/**), the docs, and mobile
# checksums/notes. The browser flash bundle (releases/firmware/**) is
# deliberately NOT packaged into releases/dist: since 2026-10-13 the only
# delivery path for firmware is the account-gated API
# (api.jkbmsr.com/v1/flash/*), which streams it from the private R2 bucket.
# The `releases/firmware/**` mirror may still exist on disk and in git
# history, but cdn.jkbmsr.com must not serve it. A guard below dies if a
# `firmware/` directory ever reappears in the packaged dist. See
# jkbmsr-private/ops/internal-notes/firmware-delivery-gate-spec.md.
#
# Usage:
#   scripts/deploy-releases.sh                  # dry run: validate + print the plan
#   scripts/deploy-releases.sh --build-only     # validate + package, publish nothing
#   scripts/deploy-releases.sh --deploy         # validate + package + publish
#
# Options:
#   --build-only     Stop after packaging into releases/dist. No credentials.
#   --deploy         Publish. This is the only flag that touches Cloudflare.
#   --dry-run        Explicit spelling of the no-argument default.
#   --no-verify      Skip the post-deploy HTTP read + hash comparison.
#   -h, --help       This text.
#
# Environment (publish only): CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID.
#
# Exit status: 0 success, 1 a step failed.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
RELEASES_DIR="$REPO_ROOT/releases"
PREFLIGHT="$SCRIPT_DIR/preflight.sh"
VERIFY="$SCRIPT_DIR/verify-publish.py"

# Load-bearing. See the header.
PAGES_PROJECT="jkbmsr-releases"
PAGES_BRANCH="main"
PUBLIC_URL="https://cdn.jkbmsr.com"

# The OTA public key every OTA-capable target must ship. Rotating it is a
# coordinated change across firmware metadata, the firmware's embedded key and
# the docs — not something to do from this script.
OTA_PUBLIC_KEY="ota/keys/public/jkbmsr-ota-p256-20260705.pem"

DIST="$RELEASES_DIR/dist"

MODE="dry-run"
NO_VERIFY=0

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
ok()   { printf '   ok    %s\n' "$*"; }
warn() { printf '   WARN  %s\n' "$*"; }
info() { printf '   ..    %s\n' "$*"; }
die()  { printf '\ndeploy-releases: FAILED — %s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; }

# The workflow gated the deploy on `if: github.ref == 'refs/heads/main'`, so a
# publish could only ever happen from main. A script has no such guarantee, so
# check it and say so — as a warning, because a tarball checkout with no git
# directory is a legitimate way to publish a hotfix, and refusing that would be
# trading a real safety property for a cosmetic one.
warn_if_not_main() {
  local branch dirty
  git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 || {
    warn "not a git checkout; cannot confirm this is the main branch"
    return 0
  }
  branch=$(git -C "$REPO_ROOT" symbolic-ref --short HEAD 2>/dev/null || true)
  case "$branch" in
    main|'') : ;;
    *) warn "current branch is '${branch:-detached HEAD}', not main." ;;
  esac
  dirty=$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null | head -5 || true)
  if [ -n "$dirty" ]; then
    warn "working tree has uncommitted changes; you are publishing what is on disk, not what is committed:"
    printf '%s\n' "$dirty" | sed 's/^/          /'
  fi
  return 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --build-only) MODE="build-only"; shift ;;
    --deploy)     MODE="deploy"; shift ;;
    --dry-run)    MODE="dry-run"; shift ;;
    --no-verify)  NO_VERIFY=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *)            die "unknown argument: $1 (try --help)" ;;
  esac
done

case "$MODE" in
  dry-run)    info "mode: dry run — nothing will be published" ;;
  build-only) info "mode: build only — nothing will be published" ;;
  deploy)     info "mode: deploy — this WILL publish to $PAGES_PROJECT/$PAGES_BRANCH" ;;
esac

[ -d "$RELEASES_DIR" ] || die "releases component not found at $RELEASES_DIR"
[ -x "$PREFLIGHT" ] || die "preflight not found or not executable: $PREFLIGHT"

# ---------------------------------------------------------------------------
# 0. Preflight
# ---------------------------------------------------------------------------
step "preflight ($PAGES_PROJECT)"
warn_if_not_main
if [ "$MODE" = "deploy" ]; then
  "$PREFLIGHT" --project "$PAGES_PROJECT" \
    || die "preflight refused to continue — see the host map above"
else
  "$PREFLIGHT" --project "$PAGES_PROJECT" --report
fi

# ---------------------------------------------------------------------------
# 1. Validate required files
#    (pages.yml, "Validate required files")
# ---------------------------------------------------------------------------
step "validate required files"
require_file() {
  [ -f "$RELEASES_DIR/$1" ] || die "missing required file: releases/$1"
  ok "$1"
}
for required in \
  README.md \
  CHANGELOG.md \
  index.html \
  404.html \
  docs/DOWNLOADS.md \
  docs/OTA_SECURITY.md \
  docs/VERIFY_FIRMWARE.md \
  _redirects
do
  require_file "$required"
done

# The public OTA verification material stays public: the signed per-target OTA
# metadata and the OTA public key. The flash bundle does not, so there is no
# firmware/<target>/latest.json requirement any more.
shopt -s nullglob
ota_latest_jsons=("$RELEASES_DIR"/ota/*-latest.json)
shopt -u nullglob
# A glob that matches nothing validates zero targets and reports success, which
# looks exactly like a healthy deploy. Assert that the OTA metadata is present.
[ "${#ota_latest_jsons[@]}" -gt 0 ] \
  || die "no ota/<target>-latest.json found — there is no public verification material to publish"
info "OTA verification metadata present for ${#ota_latest_jsons[@]} target(s)"
require_file "$OTA_PUBLIC_KEY"
ok "public OTA verification material present"

# releases/firmware/** must not be published. It may still exist on disk (the
# historical mirror), but if its absence from the package ever stops being true
# the guard before the deploy catches it. Saying it out loud here keeps the
# intent visible rather than implicit in a missing cp.
if [ -d "$RELEASES_DIR/firmware" ]; then
  info "releases/firmware/ is present on disk and deliberately NOT published (account-gated API is the only firmware delivery path)"
fi

# ---------------------------------------------------------------------------
# 2. Prepare the static artifact
#    (pages.yml, "Prepare static artifact")
# ---------------------------------------------------------------------------
# NOTE: the release-index and per-target checksum steps that used to run here
# are gone with the firmware bundle. `releases/scripts/validate_ota_metadata.py`
# (which replaced `validate_release_index.py`) and the now-unused
# `firmware/scripts/update_release_index.py` are not invoked by this deploy:
# there is no published firmware index to keep aligned, only the signed OTA
# metadata and public keys under releases/ota/. The account-gated API derives
# its catalog from R2 + D1 instead.
if [ "$MODE" = "dry-run" ]; then
  step "plan: package and publish"
  cat <<PLAN
   ..    rm -rf releases/dist
   ..    cp releases/{index.html,404.html,_headers,_redirects} releases/dist/
   ..    cp -R releases/{docs,mobile,ota} releases/dist/
   ..    find releases/dist/mobile -type f \\( -name '*.apk' -o -name '*.aab' \\) -delete
   ..    die if releases/dist/firmware exists (the firmware bundle must never be published)
   ..    cd releases && npx wrangler pages deploy dist \\
             --project-name $PAGES_PROJECT --branch $PAGES_BRANCH
   ..    python3 scripts/verify-publish.py  (real HTTP read + hash of index + OTA material)
PLAN
else
  step "prepare the static artifact (releases/dist)"
  cd "$RELEASES_DIR"

  # Cleared first on purpose. The old pipeline ran on a fresh checkout, so
  # `dist` could only hold the current build. A local working tree does not, and
  # a firmware directory left over from a previous version would be published
  # alongside the current one — on a CDN where the URL is the version number.
  rm -rf "$DIST"
  mkdir -p "$DIST"

  # 404.html is what makes Cloudflare Pages answer an unknown path with a real
  # 404 status instead of falling back to index.html at 200. Without it, `/`, a
  # bogus path and a deleted artifact were byte-identical 200s, so a 2xx proved
  # nothing and the post-cutover audit could not certify this host. Pages serves
  # 404.html for unmatched routes and does not let it shadow real assets.
  cp index.html 404.html _headers _redirects "$DIST/"

  # Public material only: the release index page, the docs, the public OTA
  # verification metadata + key, and mobile checksums/notes. Firmware bytes are
  # NOT copied — see the guard below and the header.
  cp -R docs mobile ota "$DIST/"

  # Cloudflare Pages caps individual files at 25 MiB; the signed .apk/.aab
  # already exceed that (the .aab is 40+ MiB) and are properly distributed
  # via GitHub Releases already — drop them from the Pages deploy instead of
  # failing it on every release.
  find "$DIST/mobile" -type f \( -name '*.apk' -o -name '*.aab' \) -delete

  # THE GUARD. This is the assertion that keeps the cutover from silently
  # reversing: if a future edit reintroduces a `cp -R firmware ...`, the deploy
  # would look normal and re-expose the complete flash bundle on a public host.
  # Fail loudly instead. See the header and the gate spec.
  if [ -e "$DIST/firmware" ]; then
    find "$DIST/firmware" -maxdepth 2 | sed 's/^/          /' >&2
    die "releases/dist/firmware exists — firmware must NEVER be published to cdn.jkbmsr.com; firmware is delivered only via the account-gated API (see the header)"
  fi

  file_count=$(find "$DIST" -type f | wc -l | tr -d ' ')
  size=$(du -sh "$DIST" | cut -f1)
  [ "$file_count" -gt 0 ] || die "releases/dist is empty"
  ok "packaged $file_count files ($size) into releases/dist (no firmware/)"
fi

# ---------------------------------------------------------------------------
# 5. Deploy
#    (pages.yml, "Deploy")
# ---------------------------------------------------------------------------
if [ "$MODE" != "deploy" ]; then
  step "deploy: skipped (mode is '$MODE')"
  say "   ..    would run: cd releases && npx wrangler pages deploy dist \\"
  say "   ..                   --project-name $PAGES_PROJECT --branch $PAGES_BRANCH"
else
  step "deploy to Cloudflare Pages"
  ( cd "$RELEASES_DIR" && npx wrangler pages deploy dist \
      --project-name "$PAGES_PROJECT" --branch "$PAGES_BRANCH" ) \
    || die "wrangler pages deploy failed — nothing is published unless wrangler said otherwise"
  ok "deployed releases/dist to $PAGES_PROJECT ($PAGES_BRANCH)"
fi

# ---------------------------------------------------------------------------
# 6. Verify
#
# Always a real HTTP read of the public URL plus a hash comparison. Never
# `wrangler r2 object get` or a wrangler-supplied preview URL: r2 get defaults
# to local storage, and with a token that can see two accounts it can read the
# wrong account and still report a match.
# ---------------------------------------------------------------------------
if [ "$MODE" = "deploy" ] && [ "$NO_VERIFY" -eq 0 ]; then
  step "verify the published CDN ($PUBLIC_URL)"
  # index.html plus the public OTA verification material that stays public. The
  # firmware bundle is deliberately absent — it is delivered by the
  # account-gated API from R2, not from this host — so there is nothing to
  # hash here for it. A 404 on /firmware/** is the intended state.
  verify_urls=("$PUBLIC_URL/index.html")
  verify_files=("$DIST/index.html")
  for ota_latest in "${ota_latest_jsons[@]}"; do
    rel=${ota_latest#"$RELEASES_DIR/"}
    verify_urls+=("$PUBLIC_URL/${rel}")
    verify_files+=("$DIST/${rel}")
  done
  verify_args=()
  for i in "${!verify_urls[@]}"; do
    verify_args+=(--url "${verify_urls[$i]}" --file "${verify_files[$i]}")
  done
  python3 "$VERIFY" "${verify_args[@]}" \
    || die "verification failed — the deploy landed but the public URL does not serve these bytes"
  ok "public URL serves the bytes that were deployed"
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
say "   public url       $PUBLIC_URL"
say "   ota targets      ${#ota_latest_jsons[@]}"
say "   firmware         NOT published here (account-gated API only)"
say "   staged artifact  releases/dist"
say "   published        $([ "$MODE" = deploy ] && echo yes || echo no)"
say ""
say "   next step: run 'scripts/check-all.sh' before opening a pull request;"
say "   see DEPLOY.md for the full manual procedure and the traps."
exit 0
