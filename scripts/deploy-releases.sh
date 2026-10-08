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

# One helper for every JSON read below. The original workflow inlined
# `python3 -c "import json; print(json.load(open('...'))['key'])"` a dozen
# times; same behaviour, one place to look.
json_field() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2"
}

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
# Same check, no per-file chatter: the per-target loop covers ~50 files and a
# line for each one buries the line that matters when something is missing.
require_file_quiet() {
  [ -f "$RELEASES_DIR/$1" ] || die "missing required file: releases/$1"
}
for required in \
  README.md \
  CHANGELOG.md \
  index.html \
  404.html \
  firmware/releases.json \
  firmware/hardware-targets.json \
  docs/DOWNLOADS.md \
  docs/OTA_SECURITY.md \
  docs/VERIFY_FIRMWARE.md \
  scripts/validate_release_index.py \
  _redirects
do
  require_file "$required"
done

shopt -s nullglob
latest_jsons=("$RELEASES_DIR"/firmware/*/latest.json)
shopt -u nullglob
# The original looped over `firmware/*/latest.json` without checking the glob
# matched anything: with a typo, or an empty releases/ tree, it validated zero
# targets and reported success. A CDN with no firmware on it looks exactly like
# a successful deploy, so this is checked.
[ "${#latest_jsons[@]}" -gt 0 ] \
  || die "no firmware/<target>/latest.json found — there is nothing to publish"
info "targets with a latest.json: ${#latest_jsons[@]}"

cd "$RELEASES_DIR"
for latest_json in "${latest_jsons[@]}"; do
  rel=${latest_json#"$RELEASES_DIR/"}
  target_hardware=$(json_field "$rel" targetHardware)
  version=$(json_field "$rel" currentVersion)
  public_base_url=$(json_field "$rel" publicBaseUrl)

  # A target whose latest.json points anywhere but the CDN is a misconfigured
  # release: everything downstream bakes this value into the download URLs.
  [ "$public_base_url" = "https://cdn.jkbmsr.com" ] \
    || die "$rel declares publicBaseUrl '$public_base_url', expected https://cdn.jkbmsr.com"

  require_file_quiet "firmware/${target_hardware}/v${version}/firmware.bin"
  require_file_quiet "firmware/${target_hardware}/v${version}/firmware.sha256"
  require_file_quiet "firmware/${target_hardware}/v${version}/flash-manifest.json"

  # OTA-capable targets ship the full USB/web-serial flash bundle
  # (bootloader/partitions/boot_app0) and OTA signing material; a
  # non-OTA target (currently just ESP8266 — USB reflash only, see
  # firmware/docs/esp8266-nodemcu-support.md) has neither.
  if [ -f "firmware/${target_hardware}/v${version}/firmware-metadata.json" ]; then
    require_file_quiet "firmware/${target_hardware}/v${version}/bootloader.bin"
    require_file_quiet "firmware/${target_hardware}/v${version}/partitions.bin"
    require_file_quiet "firmware/${target_hardware}/v${version}/boot_app0.bin"
    require_file_quiet "ota/${target_hardware}-latest.json"
    require_file_quiet "$OTA_PUBLIC_KEY"
  fi
  ok "$target_hardware v$version"
done
ok "every target's artifacts are present"

# ---------------------------------------------------------------------------
# 2. Validate release index consistency
#    (pages.yml, "Validate release index consistency")
# ---------------------------------------------------------------------------
step "validate release index consistency"
python3 scripts/validate_release_index.py || die "validate_release_index.py failed"
ok "firmware/releases.json agrees with every firmware/<target>/latest.json"

# ---------------------------------------------------------------------------
# 3. Verify published checksums
#    (pages.yml, "Verify published checksums")
# ---------------------------------------------------------------------------
step "verify published checksums"
for latest_json in "${latest_jsons[@]}"; do
  rel=${latest_json#"$RELEASES_DIR/"}
  target_hardware=$(json_field "$rel" targetHardware)
  version=$(json_field "$rel" currentVersion)
  ( cd "firmware/${target_hardware}/v${version}" && sha256sum -c firmware.sha256 ) \
    || die "checksum verification failed for ${target_hardware} v${version}"
  ok "${target_hardware} v${version}: firmware.sha256 matches firmware.bin"
done

# ---------------------------------------------------------------------------
# 4. Prepare the static artifact
#    (pages.yml, "Prepare static artifact")
# ---------------------------------------------------------------------------
if [ "$MODE" = "dry-run" ]; then
  step "plan: package and publish"
  cat <<PLAN
   ..    rm -rf releases/dist
   ..    cp releases/{index.html,404.html,_headers,_redirects} releases/dist/
   ..    cp releases/firmware/hardware-targets.json releases/dist/firmware/
   ..    python3  ->  releases/dist/firmware/releases.json  (one slim entry per
          target, built from each firmware/<target>/latest.json)
   ..    per target: copy firmware/<target>/latest.json and the whole
          firmware/<target>/v<version>/ directory
   ..    cp -R releases/{mobile,ota} releases/dist/
   ..    find releases/dist/mobile -type f \\( -name '*.apk' -o -name '*.aab' \\) -delete
   ..    cd releases && npx wrangler pages deploy dist \\
             --project-name $PAGES_PROJECT --branch $PAGES_BRANCH
   ..    python3 scripts/verify-publish.py  (real HTTP read + hash, every target)
PLAN
else
  step "prepare the static artifact (releases/dist)"
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

  # Kept verbatim from the workflow, intermediate file and all, so the two
  # implementations can be compared line for line.
  cp firmware/hardware-targets.json dist_hardware_targets.json
  mkdir -p "$DIST/firmware"
  cp dist_hardware_targets.json "$DIST/firmware/hardware-targets.json"
  rm dist_hardware_targets.json

  # Publish only the current browser-flash bundle per target.
  # Historical firmware remains in the release repository for
  # operational recovery but is not exposed as a browsable CDN
  # catalog. The web app's browser flasher and its hardware-model
  # selector fetch firmware/releases.json and firmware/hardware-targets.json
  # to discover flashable builds — one slim releases.json entry per target
  # here, not the full historical catalog (signatures, signing-key IDs, every
  # past version), keeps that working without bloating the deploy.
  python3 - <<'PY'
import json
import glob

releases = []
public_base_url = None
for latest_path in sorted(glob.glob("firmware/*/latest.json")):
    with open(latest_path, encoding="utf-8") as f:
        latest = json.load(f)
    public_base_url = latest["publicBaseUrl"]
    target = latest["targetHardware"]
    # latest["artifactDirectory"] ("./vX.Y.Z/") is relative to this
    # target's own firmware/<target>/ directory, but releases.json
    # lives one level up at firmware/ — prefix with the target
    # directory or the browser resolves this path one level too
    # shallow (firmware/vX.Y.Z/... instead of
    # firmware/<target>/vX.Y.Z/...) and 404s.
    releases.append({
        "version": latest["currentVersion"],
        "targetHardware": target,
        "releasedAt": latest["releasedAt"],
        "artifacts": {"flashManifest": f"./{target}/" + latest["artifactDirectory"].removeprefix("./") + "flash-manifest.json"},
    })

with open("dist/firmware/releases.json", "w", encoding="utf-8") as f:
    json.dump({"publicBaseUrl": public_base_url, "releases": releases}, f, indent=2)
    f.write("\n")
PY
  [ -f "$DIST/firmware/releases.json" ] || die "releases.json was not generated"

  for latest_json in "${latest_jsons[@]}"; do
    rel=${latest_json#"$RELEASES_DIR/"}
    target_dir=$(dirname "$rel")
    target_hardware=$(basename "$target_dir")
    version=$(json_field "$rel" currentVersion)
    mkdir -p "$DIST/firmware/${target_hardware}"
    cp "$rel" "$DIST/firmware/${target_hardware}/latest.json"
    cp -R "firmware/${target_hardware}/v${version}" "$DIST/firmware/${target_hardware}/"
  done

  cp -R mobile ota "$DIST/"

  # Cloudflare Pages caps individual files at 25 MiB; the signed .apk/.aab
  # already exceed that (the .aab is 40+ MiB) and are properly distributed
  # via GitHub Releases already — drop them from the Pages deploy instead of
  # failing it on every release.
  find "$DIST/mobile" -type f \( -name '*.apk' -o -name '*.aab' \) -delete

  file_count=$(find "$DIST" -type f | wc -l | tr -d ' ')
  size=$(du -sh "$DIST" | cut -f1)
  [ "$file_count" -gt 0 ] || die "releases/dist is empty"
  ok "packaged $file_count files ($size) into releases/dist"
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
  verify_urls=("$PUBLIC_URL/index.html" "$PUBLIC_URL/firmware/releases.json"
               "$PUBLIC_URL/firmware/hardware-targets.json")
  verify_files=("$DIST/index.html" "$DIST/firmware/releases.json"
                "$DIST/firmware/hardware-targets.json")
  for latest_json in "${latest_jsons[@]}"; do
    rel=${latest_json#"$RELEASES_DIR/"}
    target_hardware=$(basename "$(dirname "$rel")")
    version=$(json_field "$rel" currentVersion)
    verify_urls+=("$PUBLIC_URL/firmware/${target_hardware}/v${version}/firmware.bin")
    verify_files+=("$DIST/firmware/${target_hardware}/v${version}/firmware.bin")
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
say "   targets          ${#latest_jsons[@]}"
say "   staged artifact  releases/dist"
say "   published        $([ "$MODE" = deploy ] && echo yes || echo no)"
say ""
say "   next step: run 'scripts/check-all.sh' before opening a pull request;"
say "   see DEPLOY.md for the full manual procedure and the traps."
exit 0
