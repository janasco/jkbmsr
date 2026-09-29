#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Replaces the CI workflow that used to live at
# .github/workflows/ota-release.yml -- jobs `build-release` and
# `publish-release`.
#
# It signs and publishes firmware, so it is deliberately hard to run by
# accident:
#
#   * --dry-run prints the entire plan and exits 0 without touching Cloudflare,
#     R2, D1, GitHub or this repository's git state.
#   * the version is an explicit argument and must be strict MAJOR.MINOR.PATCH,
#     validated with the firmware's own isValidSemver().
#   * the OTA signing key has no default and no fallback: if
#     OTA_SIGNING_PRIVATE_KEY_B64 is absent the release stops, loudly, before
#     anything is built. The private key is not in this repository by design.
#   * CLOUDFLARE_ACCOUNT_ID must be exported and must equal the account this
#     project actually uses. See assert_cloudflare_env() for why that is not
#     paranoia.
#
# Usage:
#   ./scripts/release.sh <version> --dry-run
#   ./scripts/release.sh 0.9.2
#   ./scripts/release.sh 0.9.2 --target esp32-c3-4mb --no-push
#   ./scripts/release.sh 0.9.2 --skip-build --yes        # re-publish staged build
# ---------------------------------------------------------------------------

set -euo pipefail

# ── Fixed infrastructure identifiers ─────────────────────────────────────────
# Deliberately constants, not env-overridable defaults. A wrong account id here
# is a silent mis-publish, and the whole point of asserting it below is that it
# cannot be wrong. Changing it is a deliberate, reviewable edit to this file.
#
# On 2026-09-22 the Cloudflare account was migrated. The API token in use can
# see BOTH the old and the new account, and BOTH have an R2 bucket named
# `jkbmsr-firmware`. With only CLOUDFLARE_API_TOKEN exported,
# `wrangler r2 object put --remote` wrote to the OLD account, and a
# `wrangler r2 object get --remote` readback -- also against the old account --
# reported a perfect MATCH while the live, account-bound API kept serving the
# old object. That cost a confusing publish failure. Hence: CLOUDFLARE_ACCOUNT_ID
# is required, is asserted against the value below, and verification is done
# against URLs that name the account explicitly.
JKBMSR_CLOUDFLARE_ACCOUNT_ID="9c686ab673caa0f69af5bee930392670"
R2_BUCKET="jkbmsr-firmware"
D1_DATABASE="jkbmsr"
CLOUDFLARE_API_BASE="https://api.cloudflare.com/client/v4"

PUBLIC_BASE_URL="https://cdn.jkbmsr.com"
DOWNLOAD_URL="/api/v1/ota/firmware"

# Pinned for the same reason PlatformIO is: the workflow pinned
# `wrangler@4.107.0`, and a moving wrangler tag is how a publish path breaks
# without anyone changing this repository.
WRANGLER_VERSION="4.107.0"
PIO_PINNED_VERSION="6.1.19"
PIO_BIN="${PIO_BIN:-pio}"

# Identifiers published alongside the signature so a device can tell which key
# signed a release. OTA_SIGNING_KEY_ID was a workflow-level env in CI; it was
# also listed as a secret in firmware/.env.example because it must be bumped in
# lockstep with a key rotation. Same default, same meaning.
OTA_SIGNING_KEY_ID="${OTA_SIGNING_KEY_ID:-jkbmsr-ota-p256-20260705}"
OTA_SIGNATURE_ALGORITHM="${OTA_SIGNATURE_ALGORITHM:-ecdsa-p256-sha256}"

FIRMWARE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${FIRMWARE_ROOT}/.." && pwd)"
MIRROR_DIR="${REPO_ROOT}/releases"

# Staged build products live under .pio/, which is already gitignored, so a
# half-finished release never shows up as an untracked file.
STAGE_DIR="${FIRMWARE_ROOT}/.pio/release"

export PLATFORMIO_CORE_DIR="${PLATFORMIO_CORE_DIR:-${FIRMWARE_ROOT}/.platformio-core}"

# ── Release matrix, verbatim from the workflow ───────────────────────────────
# target_hardware | pio_env | chip_family | has_ota
RELEASE_MATRIX=$(cat <<'MATRIX'
esp32-classic-4mb|dev|ESP32|true
esp32-c3-4mb|esp32-c3-4mb|ESP32-C3|true
esp32-s3-4mb|esp32-s3-4mb|ESP32-S3|true
esp8266-uart-lite|esp8266-nodemcu|ESP8266|false
esp32-s2-4mb|esp32-s2-4mb|ESP32-S2|true
esp32-classic-8mb|esp32-classic-8mb|ESP32|true
esp32-c6-4mb|esp32-c6-4mb|ESP32-C6|true
MATRIX
)

# ── Output plumbing ──────────────────────────────────────────────────────────
VERBOSE_QUIET=0
DRY_RUN=0
SKIP_BUILD=0
DO_PUBLISH=1
DO_COMMIT=1
DO_PUSH=1
VERIFY_CDN=0
ASSUME_YES=0
SKIP_R2_VERIFY=0
PUSH_ATTEMPTS="${PUSH_ATTEMPTS:-6}"
SELECTED_TARGETS=()
BUILD_LOG_DIR=""
SIGNING_KEY_FILE=""

VERSION=""
RELEASE_TAG=""

die() {
  printf '\nrelease.sh: FATAL: %s\n' "$1" >&2
  exit 1
}

note() { printf '\n== %s\n' "$1"; }
info() { printf '   %s\n' "$1"; }
plan() { printf '   [dry-run] %s\n' "$1"; }
warn() { printf '   WARNING: %s\n' "$1" >&2; }

cleanup() {
  # The plaintext OTA signing key must not outlive the process, including on a
  # mid-flight failure. shred where available, plain rm otherwise.
  if [ -n "$SIGNING_KEY_FILE" ] && [ -f "$SIGNING_KEY_FILE" ]; then
    shred -u "$SIGNING_KEY_FILE" 2>/dev/null || rm -f "$SIGNING_KEY_FILE"
  fi
  if [ -n "$BUILD_LOG_DIR" ] && [ -d "$BUILD_LOG_DIR" ]; then
    rm -rf "$BUILD_LOG_DIR"
  fi
}
trap cleanup EXIT

usage() {
  sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ── Argument parsing ─────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run | -n) DRY_RUN=1 ;;
    --skip-build) SKIP_BUILD=1 ;;
    --no-publish) DO_PUBLISH=0; DO_COMMIT=0; DO_PUSH=0 ;;
    --no-commit) DO_COMMIT=0 ;;
    --no-push) DO_PUSH=0 ;;
    --verify-cdn) VERIFY_CDN=1 ;;
    --skip-r2-verify) SKIP_R2_VERIFY=1 ;;
    --yes | -y) ASSUME_YES=1 ;;
    --target | -t)
      [ $# -ge 2 ] || die "--target needs a targetHardware name"
      SELECTED_TARGETS+=("$2")
      shift
      ;;
    --push-attempts)
      [ $# -ge 2 ] || die "--push-attempts needs a number"
      PUSH_ATTEMPTS="$2"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*) die "unknown argument: $1 (try --help)" ;;
    *)
      [ -z "$VERSION" ] || die "unexpected extra argument: $1 (one version only)"
      VERSION="$1"
      ;;
  esac
  shift
done

[ -n "$VERSION" ] || die "a release version is required as the first argument (try --help)"
[ "$PUSH_ATTEMPTS" -ge 1 ] 2>/dev/null || die "--push-attempts must be >= 1"

for t in python3 openssl sha256sum git; do
  command -v "$t" >/dev/null 2>&1 || die "required tool not found: $t"
done

for line in $RELEASE_MATRIX; do
  name=${line%%|*}
  if [ "${#SELECTED_TARGETS[@]}" -gt 0 ]; then
    keep=0
    for want in "${SELECTED_TARGETS[@]}"; do
      [ "$want" = "$name" ] && keep=1
    done
    [ "$keep" -eq 1 ] || continue
  fi
  pio_env=$(printf '%s' "$line" | cut -d'|' -f2)
  if ! grep -q "^\[env:${pio_env}\]" "${FIRMWARE_ROOT}/platformio.ini"; then
    die "release matrix env '${pio_env}' (target ${name}) has no [env:${pio_env}] section in platformio.ini"
  fi
done
for want in "${SELECTED_TARGETS[@]:-}"; do
  [ -n "$want" ] || continue
  grep -q "^${want}|" <<<"$RELEASE_MATRIX" || die "--target '${want}' is not in the release matrix"
done

RELEASE_TAG="firmware-v${VERSION}"

# ── Banner ───────────────────────────────────────────────────────────────────
# Printed before any gate runs, so the operator sees what they invoked before
# the first check can complain about it.
printf 'release.sh: firmware %s -> tag %s\n' "$VERSION" "$RELEASE_TAG"
printf 'release.sh: PLATFORMIO_CORE_DIR=%s\n' "$PLATFORMIO_CORE_DIR"
printf 'release.sh: STAGE_DIR=%s\n' "$STAGE_DIR"
printf 'release.sh: public mirror=%s\n' "$MIRROR_DIR"
[ "$DRY_RUN" -eq 1 ] && printf 'release.sh: DRY RUN -- no build, no upload, no git.\n'

BUILD_LOG_DIR="$(mktemp -d)"

# One timestamp for the whole release, so every target's metadata, manifest,
# latest.json and index entry agree with each other. The CI legs each stamped
# their own, seconds apart, because they ran in parallel. Set RELEASED_AT to pin
# it when re-running a partially published release, so the regenerated files
# come out byte-identical.
RELEASED_AT="${RELEASED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
if [ "$DRY_RUN" -eq 1 ]; then
  info "released_at would be ${RELEASED_AT} (set RELEASED_AT to pin it)"
else
  info "released_at ${RELEASED_AT} -- ONE timestamp for the whole release, so every target's metadata, manifest and index entry agree. The CI legs each stamped their own, seconds apart, because they ran in parallel."
fi

# ── Step 1: version gates ───────────────────────────────────────────────────
# These run for real even under --dry-run: they are read-only (compile one tiny
# binary into a gitignored cache dir, read one header, read one ref), and a
# dry run that cannot tell you the version is wrong is not a useful pre-flight.
note "version"
[ "$DRY_RUN" -eq 1 ] && plan "the checks below are read-only and run even in a dry run"

# Two checks, both required. check-semver.sh asks the firmware's own
# isValidSemver() whether the string is a version, and then additionally requires
# the strict MAJOR.MINOR.PATCH form -- isValidSemver() tolerates a leading "v"
# and a prerelease suffix (a device must be able to parse whatever a corrupt
# stored config contains), and this version goes into D1 SQL, an R2 object key,
# a directory name and a GitHub tag.
if ! ./scripts/check-semver.sh --strict "$VERSION"; then
  die "'${VERSION}' is not an acceptable release version (see scripts/check-semver.sh for the two rules)"
fi

header_version=$(grep 'kFirmwareVersion' "${FIRMWARE_ROOT}/include/FirmwareVersion.h" \
  | sed -E 's/.*"([^"]+)".*/\1/')
if [ "$header_version" != "$VERSION" ]; then
  die "include/FirmwareVersion.h says '${header_version}' but the release argument is '${VERSION}' -- fix the header, or pass the version the header actually contains"
fi
info "version ${VERSION} accepted by isValidSemver() and by the strict release-sink rule"
info "include/FirmwareVersion.h agrees: kFirmwareVersion = \"${header_version}\""

# The workflow's tag guard: a run started from a firmware-v* tag that did not
# match the source version could not proceed.
if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  head_ref=$(git -C "$REPO_ROOT" describe --tags --exact-match HEAD 2>/dev/null || true)
  if [ -n "$head_ref" ] && [ "${head_ref#firmware-v}" != "$head_ref" ]; then
    if [ "$head_ref" != "$RELEASE_TAG" ]; then
      die "HEAD is tagged ${head_ref}, which does not match the expected ${RELEASE_TAG} (source version ${VERSION})"
    fi
    info "HEAD is tagged ${RELEASE_TAG}, as expected"
  fi
fi

# ── Step 2: toolchain ────────────────────────────────────────────────────────
ensure_platformio() {
  if [ "$DRY_RUN" -eq 1 ] || [ "$SKIP_BUILD" -eq 1 ]; then
    return 0
  fi
  command -v "$PIO_BIN" >/dev/null 2>&1 || die "PlatformIO ${PIO_PINNED_VERSION} is required (pip install \"platformio==${PIO_PINNED_VERSION}\")"
  have=$("$PIO_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
  [ "$have" = "$PIO_PINNED_VERSION" ] \
    || die "PlatformIO is pinned to ${PIO_PINNED_VERSION} in this repository but '${PIO_BIN}' reports '${have:-nothing}'"
}

# ── Step 3: OTA signing key ──────────────────────────────────────────────────
# Deliberately no default, no generated key, no "unsigned is fine" fallback.
# Anyone holding this key can sign firmware that real devices will accept, so
# its absence is a hard stop with instructions, not a warning.
resolve_public_key() {
  local candidate
  for candidate in \
    "${FIRMWARE_ROOT}/docs/ota-signing-public-key.pem" \
    "${MIRROR_DIR}/ota/keys/public/${OTA_SIGNING_KEY_ID}.pem"; do
    if [ -f "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

write_signing_key() {
  if [ -z "${OTA_SIGNING_PRIVATE_KEY_B64:-}" ]; then
    cat >&2 <<'MSG'

  ┌────────────────────────────────────────────────────────────────────────┐
  │ OTA_SIGNING_PRIVATE_KEY_B64 is not set. Refusing to release.            │
  └────────────────────────────────────────────────────────────────────────┘

  The OTA metadata signing key is deliberately NOT in this repository, has NO
  default, and is never substituted. Anyone holding it can sign firmware that
  deployed devices will accept, so a release without it must stop here rather
  than go out unsigned or signed with something improvised.

  Supply the base64 of the ECDSA P-256 private PEM, e.g.

      export OTA_SIGNING_PRIVATE_KEY_B64="$(base64 -w0 /secure/offline/ota-signing-private.pem)"

  Provenance and rotation: firmware/.env.example (OTA_SIGNING_PRIVATE_KEY_B64).
  The matching PUBLIC key must already be published in
  firmware/docs/ota-signing-public-key.pem -- and, more importantly, already
  embedded in the firmware running on devices, since a device verifies against
  the key baked into its own image, not against anything served here.

  This script additionally refuses to sign with a key that does not match that
  public key, so a rotated-but-unpublished key cannot reach a release.
MSG
    return 1
  fi

  mkdir -p "$STAGE_DIR"
  SIGNING_KEY_FILE="${STAGE_DIR}/ota-signing-private.pem"
  # Never echo the value, never `set -x`, never write it anywhere but this file.
  if ! printf '%s' "$OTA_SIGNING_PRIVATE_KEY_B64" | base64 -d >"$SIGNING_KEY_FILE" 2>/dev/null; then
    printf '\nrelease.sh: FATAL: OTA_SIGNING_PRIVATE_KEY_B64 is not valid base64 of a PEM file\n' >&2
    return 1
  fi
  chmod 600 "$SIGNING_KEY_FILE"
  if ! openssl pkey -in "$SIGNING_KEY_FILE" -noout -check >/dev/null 2>&1; then
    printf '\nrelease.sh: FATAL: OTA_SIGNING_PRIVATE_KEY_B64 did not decode to a usable private key\n' >&2
    return 1
  fi
  return 0
}

assert_key_matches_public() {
  local public_key="$1"
  local priv_fp pub_fp
  if ! priv_fp=$(openssl pkey -in "$SIGNING_KEY_FILE" -pubout -outform DER 2>/dev/null | sha256sum | awk '{print $1}'); then
    printf '\nrelease.sh: FATAL: could not derive a public key from OTA_SIGNING_PRIVATE_KEY_B64\n' >&2
    return 1
  fi
  if ! pub_fp=$(openssl pkey -pubin -in "$public_key" -pubout -outform DER 2>/dev/null | sha256sum | awk '{print $1}'); then
    printf '\nrelease.sh: FATAL: could not read the published public key at %s\n' "$public_key" >&2
    return 1
  fi
  if [ "$priv_fp" != "$pub_fp" ]; then
    cat >&2 <<MSG

release.sh: FATAL: the supplied OTA_SIGNING_PRIVATE_KEY_B64 does NOT match the published OTA public key (${public_key}).

  Signing now would produce metadata no device can verify: a device checks the
  key embedded in its own firmware image, not anything served from here. Either
  the wrong private key was supplied, or the signing key was rotated without
  shipping a firmware update that embeds the new public key. See the rotation
  notes in firmware/.env.example (OTA_SIGNING_KEY_ID / OTA_SIGNING_PRIVATE_KEY_B64).
MSG
    return 1
  fi
  info "signing key matches the published public key (${OTA_SIGNING_KEY_ID})"
  return 0
}

# ── Step 4: Cloudflare environment ──────────────────────────────────────────
assert_cloudflare_env() {
  if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
    printf '\nrelease.sh: FATAL: CLOUDFLARE_API_TOKEN is not set (needed for the %s R2 bucket and the %s D1 database; needs Account > Workers R2 Storage:Edit and D1:Edit)\n' \
      "$R2_BUCKET" "$D1_DATABASE" >&2
    return 1
  fi
  if [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
    cat >&2 <<MSG

  CLOUDFLARE_ACCOUNT_ID is not set. Refusing to publish.

  The API token in use can see BOTH the pre-migration Cloudflare account and the
  current one (${JKBMSR_CLOUDFLARE_ACCOUNT_ID}), and both accounts have an R2
  bucket named '${R2_BUCKET}'. With only the token exported, wrangler silently
  wrote to the wrong account, and a wrangler readback -- also against the wrong
  account -- reported a false MATCH. Export the account id; this script will
  then assert it is the right one before every remote call.

      export CLOUDFLARE_ACCOUNT_ID=${JKBMSR_CLOUDFLARE_ACCOUNT_ID}

  Provenance: jkbmsr-private/backend/.env on the release host (CLOUDFLARE_ACCOUNT_ID).
MSG
    return 1
  fi
  if [ "$CLOUDFLARE_ACCOUNT_ID" != "$JKBMSR_CLOUDFLARE_ACCOUNT_ID" ]; then
    printf '\nrelease.sh: FATAL: CLOUDFLARE_ACCOUNT_ID is %s but this project publishes to %s.\n  Refusing to publish to an account that has a same-named %s bucket.\n' \
      "'${CLOUDFLARE_ACCOUNT_ID}'" "'${JKBMSR_CLOUDFLARE_ACCOUNT_ID}'" "'${R2_BUCKET}'" >&2
    return 1
  fi

  # A token scoped only to the old account would sail through the check above
  # and then fail confusingly mid-publish. Ask Cloudflare who we are, with the
  # account id in the URL, before building anything.
  local result
  if ! result=$(python3 - "$CLOUDFLARE_API_BASE" "$CLOUDFLARE_ACCOUNT_ID" <<'PY'
import json, os, sys, urllib.error, urllib.request

base, account = sys.argv[1], sys.argv[2]
request = urllib.request.Request(
    f"{base}/accounts/{account}",
    headers={"Authorization": f"Bearer {os.environ['CLOUDFLARE_API_TOKEN']}"},
)
try:
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.load(response)
except urllib.error.HTTPError as error:
    print(f"HTTP {error.code}")
    sys.exit(1)
print(f"{payload.get('success')} {payload.get('result', {}).get('id', '')}")
PY
  ); then
    printf '\nrelease.sh: FATAL: the Cloudflare token cannot read account %s (%s) -- wrong or mis-scoped token, and publishing would fail or land in the wrong place\n' \
      "$CLOUDFLARE_ACCOUNT_ID" "${result:-no response}" >&2
    return 1
  fi
  if [ "${result%% *}" != "True" ] || [ "${result##* }" != "$CLOUDFLARE_ACCOUNT_ID" ]; then
    printf "\nrelease.sh: FATAL: Cloudflare account check returned '%s', expected 'True %s'\n" \
      "$result" "$CLOUDFLARE_ACCOUNT_ID" >&2
    return 1
  fi
  return 0
}

# Verify a published R2 object through the REST API rather than
# `wrangler r2 object get`. The REST URL contains the account id, so a
# readback cannot silently answer from the wrong account -- which is exactly the
# failure the wrangler readback hid. (The public CDN copy, published from
# releases/, gets a real unauthenticated HTTP read instead; see --verify-cdn.)
r2_object_size() {
  python3 - "$1" "$R2_BUCKET" "$CLOUDFLARE_API_BASE" <<'PY'
import json, os, sys, urllib.error, urllib.parse, urllib.request

# The bucket and the API base arrive as argv, not from the environment: they
# are shell constants, and only the token is a secret.
key, bucket, base = sys.argv[1], sys.argv[2], sys.argv[3]
account = os.environ["CLOUDFLARE_ACCOUNT_ID"]
url = (
    f"{base}/accounts/{account}"
    f"/r2/buckets/{urllib.parse.quote(bucket, safe='')}/objects/"
    f"{urllib.parse.quote(key, safe='')}"
)
request = urllib.request.Request(
    url, headers={"Authorization": f"Bearer {os.environ['CLOUDFLARE_API_TOKEN']}"}
)
try:
    with urllib.request.urlopen(request, timeout=60) as response:
        payload = json.load(response)
except urllib.error.HTTPError as error:
    print(f"HTTP {error.code}")
    sys.exit(1)
if not payload.get("success"):
    print("api reported failure")
    sys.exit(1)
print(int(payload["result"]["size"]))
PY
}

# ── Step 5: per-target build + staging ───────────────────────────────────────
# Records, one line per target, for the later phases:
declare -A TARGET_CHIP_FAMILY=() TARGET_HAS_OTA=() TARGET_SHA=() TARGET_SIGNATURE=()

target_selected() {
  [ "${#SELECTED_TARGETS[@]}" -eq 0 ] && return 0
  local want
  for want in "${SELECTED_TARGETS[@]}"; do
    [ "$want" = "$1" ] && return 0
  done
  return 1
}

r2_object_key() {
  printf 'firmware/%s/jkbmsr-%s-%s.bin' "$1" "$1" "$2"
}

object_key_for() { r2_object_key "$1" "$VERSION"; }

build_target() {
  local target="$1" pio_env="$2" chip_family="$3" has_ota="$4"
  local build_dir="${FIRMWARE_ROOT}/.pio/build/${pio_env}"
  local out="${STAGE_DIR}/${target}"
  local firmware="${build_dir}/firmware.bin"
  local asset_name="jkbmsr-${target}-${VERSION}.bin"
  local sha

  TARGET_CHIP_FAMILY["$target"]="$chip_family"
  TARGET_HAS_OTA["$target"]="$has_ota"

  info "--- ${target} (pio env: ${pio_env}, ${chip_family}, OTA: ${has_ota})"

  if [ "$SKIP_BUILD" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
    info "skipping build (--skip-build); reusing ${firmware}"
  elif [ "$DRY_RUN" -eq 1 ]; then
    plan "pio run -e ${pio_env}"
    if [ "$pio_env" = "dev" ]; then
      plan "pio test -e dev --without-uploading --without-testing   (compile only)"
      plan "pio run -e dev --target clean && pio run -e dev        (rebuild the release application after the test compile)"
    fi
    plan "verify the image: non-empty, contains the 'JKBMSR firmware starting' banner, does NOT contain the test runner"
    plan "sha256sum ${firmware} -> ${asset_name}.sha256"
    if [ "$chip_family" != "ESP8266" ]; then
      plan "collect boot_app0.bin from the arduinoespressif32 partitions tool, plus bootloader.bin and partitions.bin"
    fi
    plan "stage into ${out}/"
    TARGET_SHA["$target"]="(dry-run)"
    return 0
  else
    info "pio run -e ${pio_env}"
    "$PIO_BIN" run -e "$pio_env" >"${BUILD_LOG_DIR}/${target}.build.log" 2>&1 \
      || { tail -n 25 "${BUILD_LOG_DIR}/${target}.build.log" | sed 's/^/     /' >&2; die "${target}: pio run -e ${pio_env} failed"; }

    if [ "$pio_env" = "dev" ]; then
      # Compile-only: --without-testing means nothing is executed. Kept because
      # it is a genuine build gate -- a test that no longer compiles would
      # otherwise pass. The suites that actually RUN are the native host builds
      # in scripts/run-host-tests.sh.
      info "pio test -e dev --without-uploading --without-testing (compile only)"
      "$PIO_BIN" test -e dev --without-uploading --without-testing >"${BUILD_LOG_DIR}/${target}.tests.log" 2>&1 \
        || { tail -n 25 "${BUILD_LOG_DIR}/${target}.tests.log" | sed 's/^/     /' >&2; die "${target}: pio test -e dev failed to compile"; }

      # The test compile leaves the dev environment linked against the test
      # runner. Rebuild clean so the image that ships is the application, not
      # the test harness -- which the identity check below then proves.
      info "rebuilding the release application after the test compile"
      "$PIO_BIN" run -e dev --target clean >/dev/null 2>&1
      "$PIO_BIN" run -e dev >"${BUILD_LOG_DIR}/${target}.rebuild.log" 2>&1 \
        || { tail -n 25 "${BUILD_LOG_DIR}/${target}.rebuild.log" | sed 's/^/     /' >&2; die "${target}: clean rebuild of env:dev failed"; }
    fi

    # Release application identity. A test-runner image would flash, boot, and
    # silently do nothing on a gateway.
    [ -s "$firmware" ] || die "${target}: ${firmware} is missing or empty"
    if ! grep -aFq "JKBMSR firmware starting" "$firmware"; then
      die "${target}: release image is missing the JKBMSR application boot banner"
    fi
    if grep -aFq "test/test_version_compare/test_main.cpp" "$firmware"; then
      die "${target}: release image contains the embedded version-compare test runner"
    fi
    info "application identity verified (boot banner present, no test runner)"
  fi

  [ "$DRY_RUN" -eq 1 ] && return 0

  sha=$(sha256sum "$firmware" | awk '{print $1}')
  TARGET_SHA["$target"]="$sha"

  mkdir -p "$out"
  cp "$firmware" "${out}/firmware.bin"
  printf '%s  %s\n' "$sha" "$asset_name" >"${out}/firmware.sha256"

  if [ "$chip_family" != "ESP8266" ]; then
    # The ESP8266 has no second-stage bootloader, no partition table and no OTA
    # slot, so the flash-partition files only exist for the ESP32 families.
    cp "${build_dir}/bootloader.bin" "${out}/release-bootloader.bin"
    cp "${build_dir}/partitions.bin" "${out}/release-partitions.bin"
    # `find` rather than a fixed path: the partitions tool ships inside a
    # versioned framework package directory that moves with every platform
    # update.
    find "${PLATFORMIO_CORE_DIR:-$HOME/.platformio}/packages/framework-arduinoespressif32/tools/partitions" \
      -iname boot_app0.bin -exec cp {} "${out}/release-boot_app0.bin" \; 2>/dev/null || true
    [ -f "${out}/release-boot_app0.bin" ] || die "${target}: boot_app0.bin not found under framework-arduinoespressif32/tools/partitions"
  fi

  info "sha256 ${sha}"
}

# ── Step 6: sign OTA metadata ────────────────────────────────────────────────
sign_target() {
  local target="$1"
  local out="${STAGE_DIR}/${target}"
  local released_at="$2"
  local payload signature

  if [ "${TARGET_HAS_OTA[$target]}" != "true" ]; then
    TARGET_SIGNATURE["$target"]=""
    info "${target}: no OTA channel, nothing to sign"
    return 0
  fi

  payload=$(printf '%s\n%s\n%s\n%s' \
    "$VERSION" \
    "$target" \
    "$released_at" \
    "${TARGET_SHA[$target]}")

  # No trailing newline on the payload, and no trailing newline from base64.
  # validate-ota-release-bundle.py rebuilds this exact byte string to verify
  # the signature, so any difference here is a release-stopping mismatch.
  signature=$(printf '%s' "$payload" | openssl dgst -sha256 -sign "$SIGNING_KEY_FILE" | base64 -w0)
  TARGET_SIGNATURE["$target"]="$signature"

  cat >"${out}/firmware-metadata.json" <<JSON
{
  "version": "${VERSION}",
  "targetHardware": "${target}",
  "releasedAt": "${released_at}",
  "downloadUrl": "${DOWNLOAD_URL}",
  "sha256": "${TARGET_SHA[$target]}",
  "signature": "${signature}",
  "signingKeyId": "${OTA_SIGNING_KEY_ID}",
  "signatureAlgorithm": "${OTA_SIGNATURE_ALGORITHM}"
}
JSON
  info "${target}: metadata signed with ${OTA_SIGNING_KEY_ID} (${OTA_SIGNATURE_ALGORITHM})"
}

validate_target_bundle() {
  local target="$1"
  local released_at="$2"
  local public_key="$3"
  local out="${STAGE_DIR}/${target}"

  [ "${TARGET_HAS_OTA[$target]}" = "true" ] || return 0

  python3 "${FIRMWARE_ROOT}/scripts/validate-ota-release-bundle.py" \
    --release-dir "$out" \
    --public-key "$public_key" \
    --version "$VERSION" \
    --target-hardware "$target" \
    --released-at "$released_at" \
    --sha256 "${TARGET_SHA[$target]}" \
    --signing-key-id "$OTA_SIGNING_KEY_ID" \
    --signature-algorithm "$OTA_SIGNATURE_ALGORITHM" \
    || die "${target}: the signed OTA bundle did not validate -- not publishing"
  info "${target}: signed bundle verified against the published public key"
}

# ── Step 7: R2 ───────────────────────────────────────────────────────────────
upload_to_r2() {
  local target="$1"
  local out="${STAGE_DIR}/${target}"
  local key
  key=$(object_key_for "$target")

  if [ "$DRY_RUN" -eq 1 ]; then
    plan "npx wrangler@${WRANGLER_VERSION} r2 object put \"${R2_BUCKET}/${key}\" --file ${out}/firmware.bin --remote"
    plan "verify the object through the R2 REST API (account id in the URL, so the readback cannot come from the wrong account)"
    return 0
  fi

  # --remote is not optional in recent wrangler: without it the object is
  # written to the local .wrangler directory and the upload silently "succeeds"
  # having published nothing.
  npx --yes "wrangler@${WRANGLER_VERSION}" r2 object put "${R2_BUCKET}/${key}" \
    --file "${out}/firmware.bin" --remote \
    || die "${target}: R2 upload of ${key} failed"

  if [ "$SKIP_R2_VERIFY" -eq 1 ]; then
    warn "skipping the R2 readback (--skip-r2-verify)"
    return 0
  fi
  local expected_size actual_size
  expected_size=$(stat -c '%s' "${out}/firmware.bin")
  # Curl is broken on the release host (its config errors out with
  # "ORDER: parameter null or not set"), so every HTTP call in this script goes
  # through Python's urllib instead.
  actual_size=$(r2_object_size "$key") || die "${target}: could not read back ${key} from the R2 REST API"
  [ "$actual_size" = "$expected_size" ] \
    || die "${target}: R2 object ${key} is ${actual_size} bytes, expected ${expected_size} -- the upload did not land as intended"
  info "${target}: uploaded to ${R2_BUCKET}/${key} (${actual_size} bytes, confirmed in account ${CLOUDFLARE_ACCOUNT_ID})"
}

# ── Step 8: D1 ───────────────────────────────────────────────────────────────
update_d1() {
  local target="$1"
  local released_at="$2"
  local key
  key=$(object_key_for "$target")

  if [ "$DRY_RUN" -eq 1 ]; then
    plan "npx wrangler@${WRANGLER_VERSION} d1 execute ${D1_DATABASE} --remote --command \"<UPDATE is_latest / DELETE / INSERT firmware ...>\""
    return 0
  fi

  # Values are all either machine-generated or already pattern-checked; assert it
  # rather than trusting it, because this string is assembled as SQL.
  assert_sql_safe "$VERSION" '^[0-9]+\.[0-9]+\.[0-9]+$' "version"
  assert_sql_safe "$target" '^[a-z0-9-]+$' "target hardware"
  assert_sql_safe "${TARGET_SHA[$target]}" '^[0-9a-f]{64}$' "sha256"
  assert_sql_safe "${TARGET_SIGNATURE[$target]}" '^[A-Za-z0-9+/]+={0,2}$' "signature"
  assert_sql_safe "$OTA_SIGNING_KEY_ID" '^[A-Za-z0-9._-]+$' "signing key id"
  assert_sql_safe "$OTA_SIGNATURE_ALGORITHM" '^[A-Za-z0-9-]+$' "signature algorithm"
  assert_sql_safe "$released_at" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "released_at"

  local sql
  sql=$(cat <<SQL
UPDATE firmware SET is_latest = 0 WHERE target_hardware = '${target}';
DELETE FROM firmware WHERE version = '${VERSION}' AND target_hardware = '${target}';
INSERT INTO firmware (
  version,
  target_hardware,
  r2_object_key,
  download_url,
  sha256,
  metadata_signature,
  signing_key_id,
  signature_algorithm,
  is_latest,
  created_at
) VALUES (
  '${VERSION}',
  '${target}',
  '${key}',
  '${DOWNLOAD_URL}',
  '${TARGET_SHA[$target]}',
  '${TARGET_SIGNATURE[$target]}',
  '${OTA_SIGNING_KEY_ID}',
  '${OTA_SIGNATURE_ALGORITHM}',
  1,
  '${released_at}'
);
SQL
  )
  npx --yes "wrangler@${WRANGLER_VERSION}" d1 execute "$D1_DATABASE" --remote --command "$sql" \
    || die "${target}: D1 firmware metadata update failed"
  info "${target}: D1 firmware row written (is_latest=1, superseded 0 for this target)"
}

assert_sql_safe() {
  local value="$1" pattern="$2" label="$3"
  printf '%s' "$value" | grep -Eq "$pattern" \
    || die "refusing to build SQL: ${label} value '${value}' does not match ${pattern}"
}

# ── Step 9: GitHub release ───────────────────────────────────────────────────
create_github_release() {
  local target="$1"
  local out="${STAGE_DIR}/${target}"
  local asset_name="jkbmsr-${target}-${VERSION}"
  local assets=()

  if [ "$DRY_RUN" -eq 1 ]; then
    local extras=", ${asset_name}-metadata.json"
    [ "${TARGET_HAS_OTA[$target]}" = "true" ] || extras=""
    plan "gh release create ${RELEASE_TAG} --title \"Firmware ${VERSION}\" --notes \"...\""
    plan "   assets: ${asset_name}.bin, ${asset_name}.sha256${extras}"
    plan "   (each target's assets are copied to the real target-scoped name first, so --clobber cannot make all seven targets overwrite one asset)"
    plan "   (falls back to: gh release upload ${RELEASE_TAG} <assets> --clobber)"
    return 0
  fi

  # gh release upload's local-path#label syntax only sets a *display label* --
  # the stored asset name comes from the local file's own basename. Every target
  # stages its binary as plain "firmware.bin", so uploading with only a #label
  # would make all seven targets collide on (and --clobber overwrite) the SAME
  # stored asset, leaving whichever ran last. Copy to the real target-scoped
  # name first so each target's asset is genuinely distinct, not just
  # differently labeled.
  cp "${out}/firmware.bin" "${out}/${asset_name}.bin"
  cp "${out}/firmware.sha256" "${out}/${asset_name}.sha256"
  assets=("${out}/${asset_name}.bin" "${out}/${asset_name}.sha256")
  if [ -f "${out}/firmware-metadata.json" ]; then
    cp "${out}/firmware-metadata.json" "${out}/${asset_name}-metadata.json"
    assets+=("${out}/${asset_name}-metadata.json")
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    plan "gh release create ${RELEASE_TAG} ${assets[*]} --title \"Firmware ${VERSION}\" --notes \"...\""
    plan "   (falls back to: gh release upload ${RELEASE_TAG} ... --clobber)"
    return 0
  fi

  if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    local tag_commit
    if tag_commit=$(git -C "$REPO_ROOT" rev-parse --verify --quiet "refs/tags/${RELEASE_TAG}"); then
      if [ "$tag_commit" != "$(git -C "$REPO_ROOT" rev-parse HEAD)" ]; then
        die "tag ${RELEASE_TAG} already exists and does not point at HEAD ($(git -C "$REPO_ROOT" rev-parse --short HEAD)) -- not creating a release from the wrong commit"
      fi
    fi
  fi

  # Try create first and fall back to upload, rather than branching on
  # `gh release view` beforehand. The CI version of this needed the fallback
  # because seven legs raced; the same fallback still saves a re-run of a
  # partially published release.
  if ! gh release create "$RELEASE_TAG" "${assets[@]}" \
      --title "Firmware ${VERSION}" \
      --notes "Production release for firmware version ${VERSION} across all supported gateway hardware." 2>/dev/null; then
    gh release upload "$RELEASE_TAG" "${assets[@]}" --clobber \
      || die "${target}: could not create or update the GitHub release for ${RELEASE_TAG}"
  fi
  info "${target}: GitHub release ${RELEASE_TAG} updated (${#assets[@]} assets)"
}

# ── Step 10: the public release mirror, committed into THIS repository ───────
# ── What changed, and why ────────────────────────────────────────────────────
# The old workflow's final step cloned jkbmsr/jkbmsr-releases with a
# RELEASES_REPO_PUSH_TOKEN and pushed the public artifacts there. The public
# release artifacts now live in releases/ inside THIS repository, so the
# cross-repo clone and that token are gone: the same files are written to
# releases/ and committed to the same remote the source is already on. There is
# no second repository to authenticate to and no second remote to push.
#
# ── The stale-latest.json bug that comment warned about, and what preserves it ──
# The old step carried a long comment about a real defect: an earlier version of
# the retry loop only re-synced firmware/releases.json before regenerating it,
# leaving every OTHER target's firmware/<other-target>/latest.json exactly as
# they were at that leg's original clone -- stale, or missing entirely if a
# concurrent leg pushed in between. validate_release_index.py cross-checks
# releases.json against every target's own latest.json, so a stale or missing
# file fails validation even though the push itself would have succeeded. The
# fix at the time was `git reset --hard origin/main` before each attempt,
# because that discards the entire working tree back to current truth,
# target-scoped files included.
#
# Three things preserve that intent here, and none of them is `reset --hard`:
#
#   1. All seven targets are published by ONE process in ONE pass, so there is
#      no longer a concurrent second writer whose push can be missed.
#   2. releases/ is required to be clean before the loop starts AND re-checked
#      at the top of every attempt, and every generated file is rewritten from
#      scratch on every attempt -- target-scoped files included.
#   3. validate_release_index.py still runs on every attempt and still
#      cross-checks releases.json against every target's latest.json, so a
#      stale or missing file fails the gate instead of being published.
#
# `git reset --hard` is deliberately NOT used on a retry: this is the operator's
# working tree, not a throwaway clone, and discarding uncommitted work to win a
# push race is not a trade worth making. On a genuine non-fast-forward the
# script stops and says exactly what to run instead.
write_mirror_tree() {
  local target="$1" pio_env="$2" chip_family="$3" has_ota="$4"
  local released_at="$5"
  local out="${STAGE_DIR}/${target}"
  local version_dir="${MIRROR_DIR}/firmware/${target}/v${VERSION}"
  local metadata_field ota_metadata_json

  mkdir -p "$version_dir"
  cp "${out}/firmware.bin" "${version_dir}/firmware.bin"
  cp "${FIRMWARE_ROOT}/hardware-targets.json" "${MIRROR_DIR}/firmware/hardware-targets.json"
  printf '%s  %s\n' "${TARGET_SHA[$target]}" "firmware.bin" >"${version_dir}/firmware.sha256"

  if [ "$has_ota" = "true" ]; then
    mkdir -p "${MIRROR_DIR}/ota/keys/public"
    cp "${out}/firmware-metadata.json" "${version_dir}/firmware-metadata.json"
    cp "${out}/release-bootloader.bin" "${version_dir}/bootloader.bin"
    cp "${out}/release-partitions.bin" "${version_dir}/partitions.bin"
    cp "${out}/release-boot_app0.bin" "${version_dir}/boot_app0.bin"
    cp "${PUBLIC_KEY_PATH}" "${MIRROR_DIR}/ota/keys/public/${OTA_SIGNING_KEY_ID}.pem"
    cp "${out}/firmware-metadata.json" "${MIRROR_DIR}/ota/${target}-latest.json"
    metadata_field='"./firmware-metadata.json"'
    # Built into a variable first, then interpolated below: a heredoc nested
    # inside another heredoc's $(...) substitution is a bash syntax error, not
    # just ugly.
    ota_metadata_json=$(cat <<OTA
{
  "version": "${VERSION}",
  "targetHardware": "${target}",
  "releasedAt": "${released_at}",
  "downloadUrl": "${DOWNLOAD_URL}",
  "sha256": "${TARGET_SHA[$target]}",
  "signature": "${TARGET_SIGNATURE[$target]}",
  "signingKeyId": "${OTA_SIGNING_KEY_ID}",
  "signatureAlgorithm": "${OTA_SIGNATURE_ALGORITHM}"
}
OTA
)
  else
    metadata_field="null"
    ota_metadata_json="null"
  fi

  cat >"${version_dir}/release.json" <<JSON
{
  "version": "${VERSION}",
  "targetHardware": "${target}",
  "releasedAt": "${released_at}",
  "githubReleaseTag": "${RELEASE_TAG}",
  "artifacts": {
    "firmware": "./firmware.bin",
    "checksum": "./firmware.sha256",
    "metadata": ${metadata_field},
    "releaseNotes": "./RELEASE_NOTES.md",
    "flashManifest": "./flash-manifest.json"
  },
  "otaMetadata": ${ota_metadata_json}
}
JSON

  cat >"${version_dir}/RELEASE_NOTES.md" <<MD
# Firmware ${VERSION} — ${target}

Release date: \`${released_at}\`

$([ "$has_ota" = "true" ] && echo "This gateway hardware supports over-the-air updates; this release also went out through the OTA channel." || echo "This gateway hardware has no OTA channel (USB/web-serial reflash only) — see docs/esp8266-nodemcu-support.md.")

This public release mirrors the production artifacts published from \`firmware\`.
MD

  cat >"${MIRROR_DIR}/firmware/${target}/latest.json" <<JSON
{
  "currentVersion": "${VERSION}",
  "targetHardware": "${target}",
  "releasedAt": "${released_at}",
  "publicBaseUrl": "${PUBLIC_BASE_URL}",
  "artifactDirectory": "./v${VERSION}/",
  "checksumFile": "./v${VERSION}/firmware.sha256",
  "releaseManifest": "./v${VERSION}/release.json",
  "flashManifest": "./v${VERSION}/flash-manifest.json"
}
JSON

  # Chip-family-specific offsets generated from the checked-in hardware
  # catalog. The browser never guesses offsets from a USB adapter ID.
  python3 "${FIRMWARE_ROOT}/scripts/generate-flash-manifest.py" \
    --target "$target" \
    --version "$VERSION" \
    --output "${version_dir}/flash-manifest.json" \
    || die "${target}: generate-flash-manifest.py failed (unknown target? check firmware/hardware-targets.json)"

  (cd "$version_dir" && sha256sum -c firmware.sha256) || die "${target}: staged artifact does not match its own checksum"

  # update_release_index.py writes the RELATIVE path "firmware/releases.json",
  # and its own docstring says to run it from the root of the public release
  # tree. In the old split layout that root was a jkbmsr-releases clone; here it
  # is releases/. The script itself lives with the rest of the firmware tooling
  # in firmware/scripts/ (releases/scripts/ holds only the validator), so it is
  # invoked with releases/ as the working directory rather than copied.
  ( cd "$MIRROR_DIR" && \
    RELEASE_VERSION="${VERSION}" \
    RELEASE_TARGET_HARDWARE="${target}" \
    RELEASE_RELEASED_AT="${released_at}" \
    RELEASE_TAG="${RELEASE_TAG}" \
    RELEASE_SHA256="${TARGET_SHA[$target]}" \
    RELEASE_HAS_OTA="${has_ota}" \
    RELEASE_SIGNATURE="${TARGET_SIGNATURE[$target]:-}" \
    RELEASE_SIGNING_KEY_ID="${OTA_SIGNING_KEY_ID}" \
    RELEASE_SIGNATURE_ALGORITHM="${OTA_SIGNATURE_ALGORITHM}" \
    python3 "${FIRMWARE_ROOT}/scripts/update_release_index.py" ) \
    || die "${target}: update_release_index.py failed"
}

# The published OTA public key is a .pem. This repository's root .gitignore has
# a blanket `*.pem` rule (it is there to keep private keys out of a public
# tree), which silently ignores BOTH firmware/docs/ota-signing-public-key.pem
# and releases/ota/keys/public/<key-id>.pem. In the old split-repo layout the
# public key was copied into jkbmsr-releases, whose .gitignore had no such
# rule, so it committed fine. Copied in here it would be staged nowhere and the
# release would go out with no published verification key -- a silent,
# release-breaking difference. Catch it here rather than after the push.
assert_public_key_is_committable() {
  local path="releases/ota/keys/public/${OTA_SIGNING_KEY_ID}.pem"
  local ignored
  ignored=$(git -C "$REPO_ROOT" check-ignore -v -- "$path" 2>/dev/null || true)
  if [ -n "$ignored" ]; then
    cat >&2 <<MSG

release.sh: FATAL: the OTA public key would NOT be committed.

  '${path}' is matched by '${ignored}'.

  A release with no published verification key is a release no client can
  verify. Add a negation for the published public keys to the repository root
  .gitignore, e.g.

      !releases/ota/keys/public/*.pem
      !firmware/docs/ota-signing-public-key.pem

  (and re-add the key files), then re-run. Do not 'git add -f' a key into a tree
  whose .gitignore says every .pem is a secret -- the negation is the fix, the
  force-add hides it.
MSG
    return 1
  fi
  return 0
}

commit_mirror() {
  local branch
  branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)
  if [ "$branch" = "HEAD" ]; then
    die "detached HEAD -- check out a branch before publishing the public mirror"
  fi

  local attempt=1
  while :; do
    # Clean state for THIS attempt. See the comment above write_mirror_tree:
    # nothing target-scoped may be carried over from a previous attempt. This
    # is the hand-run equivalent of the `git reset --hard origin/main` the old
    # CI step used -- it guarantees the working tree starts from the truth
    # rather than from whatever a previous attempt left behind -- without the
    # data loss, because it refuses instead of overwriting.
    local dirty
    dirty=$(git -C "$REPO_ROOT" status --porcelain -- releases)
    if [ -n "$dirty" ]; then
      printf '%s\n' "$dirty"
      die "releases/ is not clean at attempt ${attempt} -- commit or stash those changes, then re-run. Refusing to publish on top of unknown state."
    fi

    local line target pio_env chip_family has_ota
    for line in $RELEASE_MATRIX; do
      IFS='|' read -r target pio_env chip_family has_ota <<<"$line"
      target_selected "$target" || continue
      write_mirror_tree "$target" "$pio_env" "$chip_family" "$has_ota" "$RELEASED_AT"
    done

    ( cd "$MIRROR_DIR" && python3 scripts/validate_release_index.py ) \
      || die "releases/scripts/validate_release_index.py rejected the public release tree -- nothing was committed. This is the gate that catches a stale or missing per-target latest.json."

    git -C "$REPO_ROOT" add -- releases

    if git -C "$REPO_ROOT" diff --cached --quiet; then
      info "No public release changes to commit"
      return 0
    fi

    git -C "$REPO_ROOT" commit -m "feat: publish firmware ${VERSION} release artifacts" \
      || die "git commit failed"

    if [ "$DO_PUSH" -eq 0 ]; then
      info "committed locally; not pushing (--no-push)"
      return 0
    fi

    if git -C "$REPO_ROOT" push origin "HEAD:${branch}"; then
      info "pushed releases/ to origin/${branch}"
      return 0
    fi

    git -C "$REPO_ROOT" fetch origin "$branch" || true
    if ! git -C "$REPO_ROOT" merge-base --is-ancestor "origin/${branch}" HEAD 2>/dev/null; then
      cat >&2 <<MSG

release.sh: FATAL: origin/${branch} has moved since this release started, so the push
cannot fast-forward. Nothing was forced and nothing was reset.

  Resolve it deliberately, then confirm what a client will actually download:

      git pull --rebase origin ${branch}
      git push origin ${branch}
      ./scripts/release.sh ${VERSION} --no-publish --verify-cdn --yes

  Two things to know before you do:

    * The R2 objects, the D1 rows and the GitHub release assets are ALREADY
      published at this point. This failure is only about the in-repo public
      mirror, and retrying does not roll any of it back.
    * A re-run re-signs. ECDSA is randomised by design, so regenerated
      firmware-metadata.json carries a NEW (equally valid) signature for the
      same version rather than a byte-identical tree. Do not expect 'no public
      release changes to commit' from a re-run of an already-published version.
MSG
      exit 1
    fi

    if [ "$attempt" -ge "$PUSH_ATTEMPTS" ]; then
      die "giving up on pushing to origin/${branch} after ${attempt} attempts (the remote is an ancestor of our commit, so this is a network/auth problem rather than a divergence)"
    fi
    warn "push attempt ${attempt} failed; retrying"
    sleep "$((RANDOM % 5 + 1))"
    attempt=$((attempt + 1))
  done
}

# ── Step 11: public CDN verification ─────────────────────────────────────────
# A real unauthenticated HTTP read of the published artifact, compared by
# SHA-256. This is the only verification that proves what a *client* would
# actually download, and it is deliberately not a wrangler readback.
verify_cdn() {
  if [ "$DRY_RUN" -eq 1 ]; then
    plan "GET ${PUBLIC_BASE_URL}/firmware/<target>/v${VERSION}/firmware.bin and compare SHA-256 against the local build, for every published target"
    return 0
  fi

  local line target pio_env chip_family has_ota
  local failures=0 checked=0
  for line in $RELEASE_MATRIX; do
    IFS='|' read -r target pio_env chip_family has_ota <<<"$line"
    target_selected "$target" || continue
    local remote="${PUBLIC_BASE_URL}/firmware/${target}/v${VERSION}/firmware.bin"
    local expected="${TARGET_SHA[$target]}"
    if python3 - "$remote" "$expected" <<'PY'
import hashlib, sys, urllib.error, urllib.request

url, expected = sys.argv[1], sys.argv[2]
try:
    with urllib.request.urlopen(url, timeout=120) as response:
        digest = hashlib.sha256()
        for chunk in iter(lambda: response.read(65536), b""):
            digest.update(chunk)
except urllib.error.HTTPError as error:
    print(f"HTTP {error.code}")
    sys.exit(1)
except Exception as error:  # noqa: BLE001
    print(f"fetch failed: {error}")
    sys.exit(1)
actual = digest.hexdigest()
if actual != expected:
    print(f"sha256 mismatch: got {actual}, expected {expected}")
    sys.exit(1)
print(actual)
PY
    then
      info "${target}: ${remote} matches the built image"
      checked=$((checked + 1))
    else
      printf '   %s: %s FAILED verification (published copy does not match the build)\n' "$target" "$remote" >&2
      failures=$((failures + 1))
    fi
  done
  [ "$failures" -eq 0 ] || die "${failures} published artifact(s) did not verify over HTTP against ${PUBLIC_BASE_URL}"
  info "${checked} artifact(s) verified by HTTP read and SHA-256"
}

# ── Step 12: main ────────────────────────────────────────────────────────────
# The banner, the log directory and RELEASED_AT are set up at the top of this
# script, ahead of the first gate, so the operator always sees what they
# invoked even when a gate stops them immediately.

# Every pre-flight gate runs before ANY work happens, and every one that fails
# is reported. Sequential die()s would hide the second and third problem behind
# the first, and the whole point of a pre-flight is to let the operator fix
# everything in one pass before seven firmware builds start.
PREFLIGHT_FAILURES=0

preflight_failed() {
  PREFLIGHT_FAILURES=$((PREFLIGHT_FAILURES + 1))
  printf '\n'
}

preflight() {
  local skip_remote=0
  [ "$DO_PUBLISH" -eq 0 ] && skip_remote=1

  if [ "$DRY_RUN" -eq 1 ]; then
    note "pre-flight"
    if [ "$skip_remote" -eq 1 ]; then
      plan "--no-publish: skip the Cloudflare, GitHub and public-mirror checks"
    else
      plan "assert CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID are set, and that the account id is ${JKBMSR_CLOUDFLARE_ACCOUNT_ID}"
      plan "assert the token can read that account (GET /accounts/<id>)"
      plan "assert gh is installed and authenticated (contents:write)"
      plan "assert the OTA public key is not gitignored"
    fi
    plan "assert OTA_SIGNING_PRIVATE_KEY_B64 is set, decodes, and matches the published public key"
    [ "$skip_remote" -eq 1 ] || plan "prompt for confirmation (or --yes)"
    return 0
  fi

  note "pre-flight"

  # The signing key is needed even with --no-publish: that mode still signs and
  # validates the metadata, it just stops before anything leaves the machine.
  if write_signing_key; then
    assert_key_matches_public "$PUBLIC_KEY_PATH" || preflight_failed
  else
    preflight_failed
  fi

  if [ "$skip_remote" -eq 1 ]; then
    info "--no-publish: skipping the Cloudflare, GitHub and public-mirror checks"
  else
    assert_cloudflare_env || preflight_failed

    if ! command -v gh >/dev/null 2>&1; then
      printf '\nrelease.sh: FATAL: the GitHub CLI (gh) is required to create the release assets\n' >&2
      preflight_failed
    elif [ -z "${GH_TOKEN:-}" ] && ! gh auth status >/dev/null 2>&1; then
      printf "\nrelease.sh: FATAL: gh is not authenticated -- run 'gh auth login', or export GH_TOKEN with contents:write for this repository\n" >&2
      preflight_failed
    fi

    assert_public_key_is_committable || preflight_failed
  fi

  if [ "$PREFLIGHT_FAILURES" -ne 0 ]; then
    printf '\n' >&2
    printf '┌────────────────────────────────────────────────────────────────────────┐\n' >&2
    printf '│ release.sh: %s pre-flight check(s) failed. Nothing was built,       │\n' "$PREFLIGHT_FAILURES" >&2
    printf '│ uploaded, signed, written to D1, released or committed.              │\n' >&2
    printf '└────────────────────────────────────────────────────────────────────────┘\n' >&2
    exit 1
  fi
  info "all pre-flight checks passed"
  return 0
}

# Signing key and public key: resolved up front so an obvious mistake (no key,
# no published public key) stops the run before seven firmware builds.
PUBLIC_KEY_PATH=""
if PUBLIC_KEY_PATH=$(resolve_public_key); then
  [ "$DRY_RUN" -eq 1 ] && plan "sign OTA metadata for every OTA target using OTA_SIGNING_PRIVATE_KEY_B64 (required; no default, never printed)"
else
  cat >&2 <<MSG

release.sh: FATAL: no published OTA public key found.

  Looked for:
      firmware/docs/ota-signing-public-key.pem
      releases/ota/keys/public/${OTA_SIGNING_KEY_ID}.pem

  Neither exists. That file is public and belongs in the repository, but this
  repository's root .gitignore has a blanket '*.pem' rule, so it is not
  currently committed -- see the note in assert_public_key_is_committable().

MSG
  exit 1
fi

preflight

if [ "$DO_PUBLISH" -eq 1 ] && [ "$DRY_RUN" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ]; then
  if [ ! -t 0 ]; then
    die "refusing to publish without confirmation on a non-interactive stdin -- re-run with --yes once you have read the plan above"
  fi
  target_count=0
  for line in $RELEASE_MATRIX; do
    IFS='|' read -r target _pio _chip _ota <<<"$line"
    target_selected "$target" && target_count=$((target_count + 1))
  done
  printf '\nAbout to publish %s for %s target(s) to account %s. Type "publish" to continue: ' "$VERSION" "$target_count" "$CLOUDFLARE_ACCOUNT_ID"
  read -r answer
  [ "$answer" = "publish" ] || die "aborted at the confirmation prompt"
fi

note "build and stage"
ensure_platformio
for line in $RELEASE_MATRIX; do
  IFS='|' read -r target pio_env chip_family has_ota <<<"$line"
  target_selected "$target" || continue
  build_target "$target" "$pio_env" "$chip_family" "$has_ota"
done

if [ "$DRY_RUN" -eq 0 ]; then
  note "sign and validate"
  for line in $RELEASE_MATRIX; do
    IFS='|' read -r target pio_env chip_family has_ota <<<"$line"
    target_selected "$target" || continue
    sign_target "$target" "$RELEASED_AT"
    validate_target_bundle "$target" "$RELEASED_AT" "$PUBLIC_KEY_PATH"
  done
else
  note "sign and validate"
  for line in $RELEASE_MATRIX; do
    IFS='|' read -r target pio_env chip_family has_ota <<<"$line"
    target_selected "$target" || continue
    if [ "$has_ota" = "true" ]; then
      plan "sign ${target} metadata and verify the bundle with scripts/validate-ota-release-bundle.py"
    else
      plan "${target}: no OTA channel, nothing to sign"
    fi
  done
fi

if [ "$DO_PUBLISH" -eq 0 ]; then
  note "summary"
  info "staged and signed locally only (--no-publish). Nothing was uploaded to R2, no D1 row was written, no GitHub release was created, and nothing was committed."
  for line in $RELEASE_MATRIX; do
    IFS='|' read -r target pio_env chip_family has_ota <<<"$line"
    target_selected "$target" || continue
    info "  ${target}: ${STAGE_DIR}/${target}  sha256=${TARGET_SHA[$target]:-(dry-run)}"
  done
  info ""
  info "The signed metadata for each OTA target is in the stage directory above and validates"
  info "against the published public key. To publish it later:"
  info "    ./scripts/release.sh ${VERSION} --skip-build --yes"
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  note "publish"
  for line in $RELEASE_MATRIX; do
    IFS='|' read -r target pio_env chip_family has_ota <<<"$line"
    target_selected "$target" || continue
    [ "$has_ota" = "true" ] || { plan "${target}: nothing to publish to R2 or D1 (no OTA channel); the GitHub release and the public mirror still get it"; continue; }
    upload_to_r2 "$target"
    update_d1 "$target" "$RELEASED_AT"
  done
  for line in $RELEASE_MATRIX; do
    IFS='|' read -r target pio_env chip_family has_ota <<<"$line"
    target_selected "$target" || continue
    create_github_release "$target"
  done
  note "public mirror (committed into this repository, not a second clone)"
  plan "regenerate releases/firmware/<target>/v${VERSION}/*, latest.json, ota/<target>-latest.json and releases.json for every target"
  plan "python3 releases/scripts/validate_release_index.py"
  plan "git add releases && git commit -m 'feat: publish firmware ${VERSION} release artifacts' && git push origin HEAD:<branch>"
  plan "(retry loop with a clean-tree re-check per attempt; no 'git reset --hard' -- see the comment above write_mirror_tree)"
else
  note "publish to R2"
  for line in $RELEASE_MATRIX; do
    IFS='|' read -r target pio_env chip_family has_ota <<<"$line"
    target_selected "$target" || continue
    [ "$has_ota" = "true" ] || { info "${target}: no OTA channel -- no R2 object and no D1 row, as in the old workflow"; continue; }
    upload_to_r2 "$target"
  done

  note "update D1 firmware metadata"
  for line in $RELEASE_MATRIX; do
    IFS='|' read -r target pio_env chip_family has_ota <<<"$line"
    target_selected "$target" || continue
    [ "$has_ota" = "true" ] || continue
    update_d1 "$target" "$RELEASED_AT"
  done

  note "create GitHub release ${RELEASE_TAG}"
  for line in $RELEASE_MATRIX; do
    IFS='|' read -r target pio_env chip_family has_ota <<<"$line"
    target_selected "$target" || continue
    create_github_release "$target"
  done

  note "public mirror -- committed into this repository"
  commit_mirror
fi

if [ "$VERIFY_CDN" -eq 1 ]; then
  note "verify the published copies over HTTP"
  if [ "$DO_COMMIT" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
    info "The mirror files are committed but cdn.jkbmsr.com is served by the Cloudflare Pages project"
    info "'jkbmsr-releases'. Deploy releases/ to that project first, then re-run:"
    info "    ./scripts/release.sh ${VERSION} --skip-build --no-publish --verify-cdn --yes"
  fi
  verify_cdn
fi

note "summary"
info "version     ${VERSION}"
info "tag         ${RELEASE_TAG}"
info "released_at ${RELEASED_AT}"
info "key id      ${OTA_SIGNING_KEY_ID} (${OTA_SIGNATURE_ALGORITHM})"
info "account     ${CLOUDFLARE_ACCOUNT_ID:-<not set>}"
for line in $RELEASE_MATRIX; do
  IFS='|' read -r target pio_env chip_family has_ota <<<"$line"
  target_selected "$target" || continue
  info "  ${target}  ${TARGET_SHA[$target]:-(dry-run)}  ota=${has_ota}"
done
if [ "$DO_PUSH" -eq 0 ] && [ "$DO_COMMIT" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
  info ""
  info "The public mirror is committed but NOT pushed. Nothing here is live on cdn.jkbmsr.com until it is."
fi
if [ "$DO_COMMIT" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  info ""
  info "The public mirror files were generated and validated in releases/ but NOT committed (--no-commit)."
  info "Push them yourself, or re-run without --no-commit."
fi
info ""
info "Next, by hand:"
info "  1. deploy releases/ to Cloudflare Pages project 'jkbmsr-releases' (serves cdn.jkbmsr.com)"
info "     -- NEVER to the apex or jkbmsr-web: the apex is Pages project jkbmsr-marketing (Astro), and the 2026-09-12 outage was a static export deployed into jkbmsr-web"
info "  2. ./scripts/release.sh ${VERSION} --skip-build --no-publish --verify-cdn --yes"
info "  3. ./scripts/test-production-ota.sh    (signature + checksum against the live API)"
if [ "$DRY_RUN" -eq 1 ]; then
  info ""
  info "DRY RUN: nothing was built, uploaded, written to D1, released, or committed."
fi
