#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Replaces the CI workflow that used to live at
# .github/workflows/firmware.yml -- jobs `validate`, `host-tests`, `build` and
# `build-c6`. Same checks, same order of intent, run by hand.
#
#   ./scripts/run-checks.sh --dry-run     print the plan, build nothing
#   ./scripts/run-checks.sh               everything
#   ./scripts/run-checks.sh --env idf-secure-c3 --env esp32-c6-4mb
#
# What it covers, and what replaced what:
#
#   job `validate`    -> stage `validate`
#                          python3 scripts/validate-device-profiles.py
#                          python3 scripts/validate-hardware-targets.py
#   job `host-tests`  -> stage `host-tests`
#                          ./scripts/run-host-tests.sh, plus the CI's
#                          two-known-red allowlist gate, reproduced verbatim
#   job `build`       -> stage `build`, 21 PlatformIO environments
#   job `build-c6`    -> stage `build`, 4 more (the C6 leg) -- 25 in total,
#                          which is also every [env:] in platformio.ini
#   `upload-artifact` -> the built .bin is copied into .pio/artifacts/<env>/,
#                        and a missing binary is a hard failure, which is what
#                        `if-no-files-found: error` enforced in CI
#   `actions/cache`   -> nothing to do; PlatformIO's own ~/.platformio (or
#                        $PLATFORMIO_CORE_DIR) cache is reused as-is
#   `paths:` filters  -> nothing to do; the operator chooses when to run it
#   `fail-fast:false` -> a failing env is recorded, the rest still run, and the
#                        script exits non-zero at the end with a per-env table
# ---------------------------------------------------------------------------

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# PlatformIO pinned on purpose. An unpinned PlatformIO broke the firmware
# matrix for two weeks (a core/platform update landed under a moving tag), so
# this is deliberately exact and the script refuses to proceed on any other
# version.
PIO_PINNED_VERSION="6.1.19"
PIO_BIN="${PIO_BIN:-pio}"

# Keep the toolchain inside the repository's own gitignored .platformio-core/
# unless the operator already chose a location (the repo docs use
# PLATFORMIO_CORE_DIR=/tmp/platformio).
export PLATFORMIO_CORE_DIR="${PLATFORMIO_CORE_DIR:-${ROOT}/.platformio-core}"

ARTIFACT_DIR="${ARTIFACT_DIR:-${ROOT}/.pio/artifacts}"

# ── The two suites that are KNOWN RED ────────────────────────────────────────
# Neither is a JK-BMS path and neither ships, so a red run of these two is the
# current expected state, not a regression:
#
#   test_daly_d2_decoder -- the test fixtures disagree with the decoder's own
#       length constants, so the "parses successfully" assertions cannot hold.
#   test_ks_bms_decoder   -- a one-byte SOH-threshold disagreement in the
#       status-frame test.
#
# The old CI job grepped for BUILD-FAIL/FAIL and filtered exactly these two
# names out; anything else failed the job. That allowlist -- and nothing looser
# -- is reproduced below, and both suites are named in the output on every run
# so a red run is never mistaken for a fresh regression.
KNOWN_RED_SUITES=(
  test_daly_d2_decoder
  test_ks_bms_decoder
)

# ── Build matrix, verbatim from the workflow ─────────────────────────────────
# env | upload-firmware.bin | compile-only tests | needs Secure Boot dev key
# (`needs_key` was `needs_key` in the matrix; the two C6-only jobs in `build-c6`
# are folded in here, which is what fail-fast:false across two jobs amounted to.)
BUILD_MATRIX=$(cat <<'MATRIX'
dev|yes|yes|no
esp8266-nodemcu|yes|no|no
esp32-c3-4mb|yes|no|no
esp32-s3-4mb|yes|no|no
esp32-s2-4mb|yes|no|no
esp32-classic-8mb|yes|no|no
idf|no|no|no
idf-secure|yes|no|no
idf-secureboot|no|no|yes
idf-s3|no|no|no
idf-secure-s3|yes|no|no
idf-secureboot-s3|no|no|yes
idf-c3|no|no|no
idf-secure-c3|yes|no|no
idf-secureboot-c3|no|no|yes
idf-s2|no|no|no
idf-secure-s2|yes|no|no
idf-secureboot-s2|no|no|yes
idf-8mb|no|no|no
idf-secure-8mb|yes|no|no
idf-secureboot-8mb|no|no|yes
esp32-c6-4mb|yes|no|no
idf-c6|no|no|no
idf-secure-c6|yes|no|no
idf-secureboot-c6|no|no|yes
MATRIX
)

DRY_RUN=0
INSTALL_PIO=1
SELECTED_ENVS=()
LOG_DIR=""

usage() {
  sed -n '2,29p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'run-checks: %s\n' "$1" >&2
  exit 1
}

note() { printf '\n== %s\n' "$1"; }
info() { printf '   %s\n' "$1"; }
plan() { printf '   [dry-run] %s\n' "$1"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run | -n) DRY_RUN=1 ;;
    --no-install-pio) INSTALL_PIO=0 ;;
    --env | -e)
      [ $# -ge 2 ] || die "--env needs an environment name"
      SELECTED_ENVS+=("$2")
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
  shift
done

# ── Build matrix self-consistency ───────────────────────────────────────────
# Two failure modes this catches, both of which CI could not see because it
# regenerated the matrix from YAML that PlatformIO never read:
#   * a matrix env that does not exist in platformio.ini -> pio run fails
#     confusingly much later, or (worse) is silently skipped;
#   * a new env in platformio.ini that nobody added to the matrix -> silently
#     never built. run-host-tests.sh has the same guard for the same reason.
for line in $BUILD_MATRIX; do
  env_name=${line%%|*}
  if ! grep -q "^\[env:${env_name}\]" platformio.ini; then
    die "matrix env '${env_name}' has no [env:${env_name}] section in platformio.ini"
  fi
done
for env_name in $(sed -n 's/^\[env:\([^]]*\)\].*/\1/p' platformio.ini | sort); do
  if ! grep -q "^${env_name}|" <<<"$BUILD_MATRIX"; then
    die "platformio.ini defines [env:${env_name}] but it is not in the build matrix -- add it to BUILD_MATRIX in $0"
  fi
done

# ── Environment selection ───────────────────────────────────────────────────
if [ "${#SELECTED_ENVS[@]}" -gt 0 ]; then
  for wanted in "${SELECTED_ENVS[@]}"; do
    found=0
    for line in $BUILD_MATRIX; do
      [ "${line%%|*}" = "$wanted" ] && found=1
    done
    [ "$found" -eq 1 ] || die "--env '${wanted}' is not in the build matrix"
  done
fi

env_selected() {
  [ "${#SELECTED_ENVS[@]}" -eq 0 ] && return 0
  local wanted
  for wanted in "${SELECTED_ENVS[@]}"; do
    [ "$wanted" = "$1" ] && return 0
  done
  return 1
}

# ── Per-env bookkeeping ─────────────────────────────────────────────────────
declare -a RESULT_ENV=() RESULT_STATE=() RESULT_NOTE=()
FAILURES=0

record() {
  RESULT_ENV+=("$1")
  RESULT_STATE+=("$2")
  RESULT_NOTE+=("${3:-}")
  # SKIP is a dry-run state, not a failure -- the step is accounted for, it just
  # did not run. Only FAIL counts.
  [ "$2" = "FAIL" ] && FAILURES=$((FAILURES + 1))
  return 0
}

# ── PlatformIO ──────────────────────────────────────────────────────────────
pio_version() {
  "$PIO_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true
}

ensure_platformio() {
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$INSTALL_PIO" -eq 1 ]; then
      plan "pip install \"platformio==${PIO_PINNED_VERSION}\" (and verify \`pio --version\` reports exactly it)"
    else
      plan "skip PlatformIO installation (--no-install-pio)"
    fi
    if [ "$INSTALL_PIO" -eq 1 ] && command -v "$PIO_BIN" >/dev/null 2>&1; then
      plan "note: $PIO_BIN is present and reports $(pio_version)"
    fi
    return 0
  fi

  command -v python3 >/dev/null 2>&1 || die "python3 not found"

  local have=""
  command -v "$PIO_BIN" >/dev/null 2>&1 && have="$(pio_version)"

  if [ "$have" = "$PIO_PINNED_VERSION" ]; then
    info "PlatformIO ${PIO_PINNED_VERSION} already installed"
    return 0
  fi

  if [ "$INSTALL_PIO" -eq 0 ]; then
    die "PlatformIO ${PIO_PINNED_VERSION} is required but '${PIO_BIN}' reports '${have:-nothing}' (remove --no-install-pio, or install it yourself)"
  fi

  if [ -n "$have" ]; then
    info "PlatformIO '${have}' installed, but this matrix is pinned to ${PIO_PINNED_VERSION}"
  fi
  info "Installing platformio==${PIO_PINNED_VERSION} (pinned deliberately: unpinned PlatformIO broke this matrix for two weeks)"
  python3 -m pip install "platformio==${PIO_PINNED_VERSION}"

  command -v "$PIO_BIN" >/dev/null 2>&1 || die "platformio installed but '${PIO_BIN}' is still not on PATH"
  have="$(pio_version)"
  [ "$have" = "$PIO_PINNED_VERSION" ] \
    || die "expected PlatformIO ${PIO_PINNED_VERSION}, got '${have:-unknown}' -- refusing to build on an unpinned toolchain"
  info "PlatformIO ${PIO_PINNED_VERSION} ready"
}

# ── Stage: validate ─────────────────────────────────────────────────────────
run_validate() {
  note "validate -- supported-device profiles and gateway hardware targets"
  if [ "$DRY_RUN" -eq 1 ]; then
    plan "python3 scripts/validate-device-profiles.py"
    plan "python3 scripts/validate-hardware-targets.py"
    return 0
  fi
  python3 scripts/validate-device-profiles.py
  python3 scripts/validate-hardware-targets.py
}

# ── Stage: host tests ───────────────────────────────────────────────────────
run_host_tests() {
  note "host-tests -- native suites under AddressSanitizer + UndefinedBehaviorSanitizer"

  # CI invoked this as ./scripts/run-host-tests.sh. Some working copies have
  # lost the executable bit, so fall back to `bash <script>` rather than failing
  # on a mode bit; the suites themselves are what matter.
  local runner=()
  if [ -x ./scripts/run-host-tests.sh ]; then
    runner=(./scripts/run-host-tests.sh)
  else
    info "./scripts/run-host-tests.sh is not executable in this checkout; running it with bash"
    runner=(bash ./scripts/run-host-tests.sh)
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    plan "${runner[*]}"
    plan "allowlist gate: fail only on BUILD-FAIL/FAIL lines that are not one of: ${KNOWN_RED_SUITES[*]}"
    return 0
  fi

  # `|| true` then grep, exactly as CI did: the script's own exit status is
  # non-zero purely because of the two known-red suites.
  local out
  out=$("${runner[@]}" 2>&1) || true
  printf '%s\n' "$out"

  local unexpected
  unexpected=$(printf '%s\n' "$out" \
    | grep -E 'BUILD-FAIL|FAIL ' \
    | grep -vE "$(IFS='|'; printf '%s' "${KNOWN_RED_SUITES[*]}")" || true)

  info ""
  info "Documented non-shipping suites, expected red in this repository:"
  local suite
  for suite in "${KNOWN_RED_SUITES[@]}"; do
    info "  - ${suite}   (see the KNOWN_RED_SUITES block at the top of this script)"
  done

  if [ -n "$unexpected" ]; then
    printf '\nUnexpected suite regression:\n' >&2
    printf '%s\n' "$unexpected" >&2
    record "host-tests" FAIL "unexpected suite failure"
    return 1
  fi

  info ""
  info "Only the two documented non-shipping suites are failing."
  record "host-tests" PASS ""
  return 0
}

# ── Stage: build ────────────────────────────────────────────────────────────
run_build() {
  note "build -- PlatformIO matrix (every env in BUILD_MATRIX, narrowed by --env)"

  # Deliberately last, not first: the profile/target validators and the native
  # host suites need no PlatformIO, no ESP toolchain and no hardware, so a
  # contributor without PlatformIO installed still gets those two stages run
  # before being asked to install a pinned toolchain.
  ensure_platformio

  local secure_boot_key_ready=0
  local line env_name upload run_tests needs_key
  local started=0

  for line in $BUILD_MATRIX; do
    IFS='|' read -r env_name upload run_tests needs_key <<<"$line"
    env_selected "$env_name" || continue

    if [ "$started" -eq 0 ]; then
      started=1
      LOG_DIR="$(mktemp -d)"
      trap 'rm -rf "$LOG_DIR"' EXIT
    fi

    # The workflow ran this step only for needs_key envs, immediately before
    # the matching `pio run`. The generator is idempotent -- it exits 0 if
    # keys/secure_boot_signing_key.pem already exists -- so calling it once up
    # front for the whole matrix is equivalent and cheaper.
    if [ "$needs_key" = "yes" ] && [ "$secure_boot_key_ready" -eq 0 ]; then
      if [ -x ./scripts/generate-secure-boot-dev-key.sh ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
          plan "./scripts/generate-secure-boot-dev-key.sh  (dev-only Secure Boot v2 key; writes firmware/keys/secure_boot_signing_key.pem, gitignored, never a production key)"
        else
          info "Generating the Secure Boot v2 *development* key (ignored if it already exists)"
          ./scripts/generate-secure-boot-dev-key.sh
        fi
      else
        die "missing ./scripts/generate-secure-boot-dev-key.sh, required by envs: idf-secureboot, idf-secureboot-c3, idf-secureboot-s2, idf-secureboot-s3, idf-secureboot-c6, idf-secureboot-8mb"
      fi
      secure_boot_key_ready=1
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
      plan "pio run -e ${env_name}   (firmware.bin artifact: ${upload}; compile-only tests: ${run_tests})"
      record "$env_name" SKIP "dry-run"
      continue
    fi

    info "pio run -e ${env_name}"
    if "$PIO_BIN" run -e "$env_name" >"${LOG_DIR}/${env_name}.log" 2>&1; then
      info "  ok"
    else
      info "  FAILED -- last lines of ${LOG_DIR}/${env_name}.log:"
      tail -n 15 "${LOG_DIR}/${env_name}.log" | sed 's/^/    /' || true
      record "$env_name" FAIL "pio run failed"
      continue
    fi

    # Compile-only: --without-testing means PlatformIO compiles the suites and
    # executes none of them. The suites that actually RUN are the native host
    # builds in the host-tests stage; a "[PASSED]" line from this step is a
    # compile result, not a test result. Kept because it is a real build gate
    # (a test that no longer compiles used to pass this step).
    if [ "$run_tests" = "yes" ]; then
      info "  pio test -e dev --without-uploading --without-testing (compile only)"
      if "$PIO_BIN" test -e dev --without-uploading --without-testing >"${LOG_DIR}/${env_name}.tests.log" 2>&1; then
        info "  ok (compiled; not executed -- see the host-tests stage)"
      else
        tail -n 15 "${LOG_DIR}/${env_name}.tests.log" | sed 's/^/    /' || true
        record "$env_name" FAIL "pio test -e dev failed to compile"
        continue
      fi
    fi

    if [ "$upload" = "yes" ]; then
      # Stands in for the workflow's upload-artifact step. The point of the
      # original was `if-no-files-found: error` -- a matrix leg that "succeeded"
      # without producing a .bin is a failure, and that is preserved here.
      local built="${ROOT}/.pio/build/${env_name}/firmware.bin"
      if [ ! -s "$built" ]; then
        record "$env_name" FAIL "built but no firmware.bin at ${built}"
        continue
      fi
      mkdir -p "${ARTIFACT_DIR}/${env_name}"
      cp "$built" "${ARTIFACT_DIR}/${env_name}/firmware.bin"
      (cd "${ARTIFACT_DIR}/${env_name}" && sha256sum firmware.bin > firmware.sha256)
    fi

    record "$env_name" PASS ""
  done

  if [ "$started" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
    info ""
    info "Build logs kept in ${LOG_DIR} until this script exits."
    info "Firmware binaries staged under ${ARTIFACT_DIR}"
  fi
}

# ── Summary ─────────────────────────────────────────────────────────────────
print_summary() {
  printf '\n'
  printf -- '----------------------------------------------------------------\n'
  printf '%-22s %-6s %s\n' "STEP" "STATE" "NOTE"
  printf -- '----------------------------------------------------------------\n'
  local i
  for i in "${!RESULT_ENV[@]}"; do
    printf '%-22s %-6s %s\n' "${RESULT_ENV[$i]}" "${RESULT_STATE[$i]}" "${RESULT_NOTE[$i]}"
  done
  printf -- '----------------------------------------------------------------\n'
  printf '%d step(s), %d failure(s).\n' "${#RESULT_ENV[@]}" "$FAILURES"

  if [ "$FAILURES" -ne 0 ]; then
    printf '\nrun-checks: FAILED\n'
    return 1
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '\nrun-checks: dry run only. Nothing was built, installed or uploaded.\n'
    return 0
  fi

  printf '\nrun-checks: all green. A release is still not authorised by this script:\n'
  printf 'run-checks: use ./scripts/release.sh <version> for that.\n'
  return 0
}

# ── Main ────────────────────────────────────────────────────────────────────
printf 'run-checks: firmware (%s)\n' "$(basename "$(git rev-parse --show-toplevel 2>/dev/null || printf 'not a git checkout')")/$(basename "$ROOT")"
printf 'run-checks: PLATFORMIO_CORE_DIR=%s\n' "$PLATFORMIO_CORE_DIR"
[ "$DRY_RUN" -eq 1 ] && printf 'run-checks: DRY RUN -- no build, no install, no upload.\n'

run_validate
run_host_tests || true
run_build
print_summary
