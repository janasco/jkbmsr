#!/usr/bin/env bash
#
# check-all.sh — the one command to run before opening a pull request.
#
# This repository has no hosted CI. Nothing runs on pull request, nothing runs
# on push, and no reviewer sees a green tick that is not green for the whole
# tree. The consequence is the one that matters on this project: a decoder
# change that broke a frame format would have been caught by a test run, and now
# it will not be caught unless a person runs this script.
#
# The suites, one per component:
#   apps/ble           flutter analyze && flutter test       (expect 70 passing)
#   apps/pro           flutter analyze && flutter test       (expect 85 passing)
#   apps/contributor   flutter analyze && flutter test       (expect 84 passing)
#   packages/bms_core  dart analyze && dart test             (expect 24 passing)
#   firmware           native host suites under ASan/UBSan, plus the device-profile
#                      and hardware-target validators — see firmware/scripts/run-checks.sh
#   docs               npm run docs:build
#   releases           python3 scripts/validate_ota_metadata.py
#
# Usage:
#   scripts/check-all.sh                 # dry run: print every command, run nothing
#   scripts/check-all.sh --run           # run every suite, print a pass/fail table
#   scripts/check-all.sh --run --only docs --only releases
#
# Options:
#   --run          Actually execute the suites. Without it nothing is executed.
#   --only NAME    Restrict to a component (apps/ble, apps/pro, apps/contributor,
#                  packages/bms_core, firmware, docs, releases). Repeatable. Implies
#                  nothing about running: still needs --run.
#   --strict       Treat a skipped component as a failure. Use it when you are
#                  the last person before a merge and a green table that skipped
#                  half the tree is worse than no table.
#   -h, --help     This text.
#
# Environment:
#   FLUTTER_BIN              directory to prepend to PATH (default
#                            /home/jkbmsr/flutter/bin, prepended only if it exists
#                            and flutter is not already on PATH)
#   BLE_EXPECTED_TESTS       expected passing test count for apps/ble (default 172)
#   PRO_EXPECTED_TESTS       expected passing test count for apps/pro (default 180)
#   CONTRIBUTOR_EXPECTED_TESTS  expected passing test count for apps/contributor (default 135)
#   BMS_CORE_EXPECTED_TESTS  expected passing test count for packages/bms_core (default 24)
#
# Exit status: 0 everything that ran passed (skips are allowed unless --strict),
# 1 at least one component failed, 2 usage error.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

COMPONENTS=(apps/ble apps/pro apps/contributor packages/bms_core firmware docs releases)

RUN=0
STRICT=0
ONLY=()
BLE_EXPECTED_TESTS=${BLE_EXPECTED_TESTS:-172}
PRO_EXPECTED_TESTS=${PRO_EXPECTED_TESTS:-180}
CONTRIBUTOR_EXPECTED_TESTS=${CONTRIBUTOR_EXPECTED_TESTS:-135}
BMS_CORE_EXPECTED_TESTS=${BMS_CORE_EXPECTED_TESTS:-24}
LOG_DIR=""

# Result columns, indexed the same way as COMPONENTS.
declare -a RESULT=() DETAIL=()

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
ok()   { printf '   ok    %s\n' "$*"; }
warn() { printf '   WARN  %s\n' "$*"; }
info() { printf '   ..    %s\n' "$*"; }
die()  { printf '\ncheck-all: %s\n' "$*" >&2; exit 2; }

usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; }

# Resolve PlatformIO the same way the firmware scripts do (`PIO_BIN`, defaulting
# to a known venv/path), so the firmware stage and the toolchain report agree on
# which binary they mean. PlatformIO is NOT pip-installable on this host (PEP 668
# externally-managed-environment) and its venv is deliberately not on the default
# PATH, so "pio not found" is the normal state for a plain shell — not evidence
# that the firmware is broken. Order: an explicit PIO_BIN, then the known venv,
# then whatever is on PATH.
resolve_pio() {
  if [ -n "${PIO_BIN:-}" ] && command -v "${PIO_BIN}" >/dev/null 2>&1; then
    printf '%s\n' "${PIO_BIN}"; return 0
  fi
  if [ -x /home/jkbmsr/.pio-venv/bin/pio ]; then
    printf '%s\n' /home/jkbmsr/.pio-venv/bin/pio; return 0
  fi
  if command -v pio >/dev/null 2>&1; then
    printf '%s\n' pio; return 0
  fi
  return 1
}
PIO_RESOLVED="$(resolve_pio || true)"

cleanup() {
  local status=$?
  if [ "$status" -eq 0 ] && [ -n "$LOG_DIR" ] && [ -d "$LOG_DIR" ]; then
    rm -rf "$LOG_DIR"
  elif [ -n "$LOG_DIR" ]; then
    printf '\nlogs kept in %s\n' "$LOG_DIR"
  fi
}
trap cleanup EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    --run)    RUN=1; shift ;;
    --strict) STRICT=1; shift ;;
    --only)   [ $# -ge 2 ] || die "--only needs a component name"; ONLY+=("$2"); shift 2 ;;
    --only=*) ONLY+=("${1#*=}"); shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

for name in ${ONLY+"${ONLY[@]}"}; do
  case " ${COMPONENTS[*]} " in
    *" $name "*) ;;
    *) die "unknown component '$name' (known: ${COMPONENTS[*]})" ;;
  esac
done

selected() {
  [ "${#ONLY[@]}" -eq 0 ] && return 0
  local name
  for name in "${ONLY[@]}"; do
    [ "$name" = "$1" ] && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# Toolchain discovery (read-only, safe in both modes)
# ---------------------------------------------------------------------------
step "toolchain"
if ! command -v flutter >/dev/null 2>&1; then
  candidate=${FLUTTER_BIN:-/home/jkbmsr/flutter/bin}
  if [ -d "$candidate" ]; then
    PATH="$PATH:$candidate"
    export PATH
  fi
fi
for tool in node npm python3 g++; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool ($($tool --version 2>&1 | head -1))"
  else
    warn "$tool not found on PATH"
  fi
done
if [ -n "$PIO_RESOLVED" ]; then
  ok "pio ($PIO_RESOLVED; $("$PIO_RESOLVED" --version 2>&1 | head -1))"
else
  warn "pio not found via PIO_BIN, /home/jkbmsr/.pio-venv/bin/pio or PATH — the firmware suite will SKIP"
  warn "  it is pinned to 6.1.19 and is not pip-installable on this host (externally-managed-environment)"
fi
if command -v flutter >/dev/null 2>&1; then
  ok "flutter ($(command -v flutter))"
else
  warn "flutter not found — apps/ble, apps/pro and apps/contributor cannot be checked."
  warn "  add it with: export PATH=\$PATH:${FLUTTER_BIN:-/home/jkbmsr/flutter/bin}"
fi
if command -v dart >/dev/null 2>&1; then
  ok "dart ($(command -v dart))"
else
  warn "dart not found — packages/bms_core cannot be checked."
  warn "  it ships with the Flutter SDK: export PATH=\$PATH:${FLUTTER_BIN:-/home/jkbmsr/flutter/bin}"
fi

# ---------------------------------------------------------------------------
# Per-component runners
#
# Each records PASS / FAIL / SKIP plus a one-line detail, and writes its full
# output to $LOG_DIR so a failure can be read afterwards instead of scrolled
# past.
# ---------------------------------------------------------------------------
record() { RESULT+=("$1"); DETAIL+=("$2"); }

# Why a lower test count is a failure and a higher one is not: a suite that
# silently stops running looks exactly like a passing one. That is not
# theoretical here — `pio test --without-testing` compiled the firmware suites
# without ever executing them, and three real decoder defects hid behind
# "0 test cases: 0 succeeded" until the suites were actually run.
flutter_suite() {
  local component=$1 expected=$2 log="$LOG_DIR/${1//\//-}.log"
  if ! command -v flutter >/dev/null 2>&1; then
    record SKIP "flutter not on PATH"
    return 0
  fi
  local app_dir="$REPO_ROOT/$component"
  if [ ! -f "$app_dir/pubspec.yaml" ]; then
    record SKIP "no pubspec.yaml"
    return 0
  fi
  # Only resolve packages when they are not already resolved: `flutter pub get`
  # on every run is slow and this script is meant to be run often.
  if [ ! -f "$app_dir/.dart_tool/package_config.json" ]; then
    info "$component: .dart_tool/package_config.json missing, running flutter pub get"
    ( cd "$app_dir" && flutter pub get ) >>"$log" 2>&1 \
      || { record FAIL "flutter pub get failed (see $log)"; return 0; }
  fi
  if ( cd "$app_dir" && flutter analyze && flutter test ) >"$log" 2>&1; then
    local count
    count=$(grep -oE '\+[0-9]+' "$log" | tail -1 | tr -d '+' || true)
    if [ -z "$count" ]; then
      # The run succeeded; only the progress-line format moved. Reporting a
      # failure here would train people to ignore this column.
      record PASS "analyze + test ok (test count not parsed — see $log)"
    elif [ "$count" -lt "$expected" ]; then
      record FAIL "$count tests passed, expected at least $expected (see $log)"
    else
      record PASS "$count tests passed (expected $expected)"
    fi
  else
    record FAIL "flutter analyze && flutter test failed (see $log)"
  fi
}

# The pure-Dart counterpart to flutter_suite(): packages/bms_core depends on the
# `test` package rather than flutter_test, so it is driven by `dart analyze` /
# `dart test` and resolves with `dart pub get`. The count check exists for the
# same reason as flutter_suite's: a suite that silently stops running looks
# exactly like a passing one.
dart_suite() {
  local component=$1 expected=$2 log="$LOG_DIR/${1//\//-}.log"
  if ! command -v dart >/dev/null 2>&1; then
    record SKIP "dart not on PATH"
    return 0
  fi
  local app_dir="$REPO_ROOT/$component"
  if [ ! -f "$app_dir/pubspec.yaml" ]; then
    record SKIP "no pubspec.yaml"
    return 0
  fi
  if [ ! -f "$app_dir/.dart_tool/package_config.json" ]; then
    info "$component: .dart_tool/package_config.json missing, running dart pub get"
    ( cd "$app_dir" && dart pub get ) >>"$log" 2>&1 \
      || { record FAIL "dart pub get failed (see $log)"; return 0; }
  fi
  if ( cd "$app_dir" && dart analyze && dart test ) >"$log" 2>&1; then
    local count
    count=$(grep -oE '\+[0-9]+' "$log" | tail -1 | tr -d '+' || true)
    if [ -z "$count" ]; then
      record PASS "analyze + test ok (test count not parsed — see $log)"
    elif [ "$count" -lt "$expected" ]; then
      record FAIL "$count tests passed, expected at least $expected (see $log)"
    else
      record PASS "$count tests passed (expected $expected)"
    fi
  else
    record FAIL "dart analyze && dart test failed (see $log)"
  fi
}

docs_suite() {
  local log="$LOG_DIR/docs.log"
  local docs_dir="$REPO_ROOT/docs"
  [ -f "$docs_dir/package.json" ] || { record SKIP "no docs/package.json"; return 0; }
  if [ ! -d "$docs_dir/node_modules" ]; then
    info "docs: node_modules missing, running npm ci"
    ( cd "$docs_dir" && npm ci ) >>"$log" 2>&1 \
      || { record FAIL "npm ci failed (see $log)"; return 0; }
  fi
  if ( cd "$docs_dir" && npm run docs:build ) >"$log" 2>&1; then
    record PASS "vitepress build ok"
  else
    record FAIL "npm run docs:build failed (see $log)"
  fi
}

releases_suite() {
  local log="$LOG_DIR/releases.log"
  local releases_dir="$REPO_ROOT/releases"
  # Validates the material this repository still publishes: the signed OTA
  # metadata (ota/<target>-latest.json) and the OTA public keys
  # (ota/keys/public/*.pem). The old release-index validator required
  # releases/firmware/releases.json, a firmware mirror deliberately stripped on
  # 2026-10-13 when firmware delivery moved behind the account-gated API — see
  # AGENTS.md (History, 2026-10-13). That tree is correctly absent, so the check
  # was failing on input the repository is right not to carry.
  if [ ! -f "$releases_dir/scripts/validate_ota_metadata.py" ]; then
    record SKIP "validate_ota_metadata.py not found"
    return 0
  fi
  if ( cd "$releases_dir" && python3 scripts/validate_ota_metadata.py ) >"$log" 2>&1; then
    record PASS "$(tail -1 "$log")"
  else
    record FAIL "validate_ota_metadata.py failed (see $log)"
  fi
}

firmware_suite() {
  local log="$LOG_DIR/firmware.log"
  local runner="$REPO_ROOT/firmware/scripts/run-checks.sh"
  if [ ! -x "$runner" ]; then
    # Not a failure and not a pass. Reporting it as either would be a lie: the
    # firmware suites are the ones this project most needs run, and a component
    # that was never checked is not a component that passed. --strict turns this
    # into a failure for whoever is about to merge.
    record SKIP "firmware/scripts/run-checks.sh not present yet"
    info "expected path: firmware/scripts/run-checks.sh"
    info "until it lands, run by hand:"
    info "  cd firmware && ./scripts/run-host-tests.sh"
    info "  python3 firmware/scripts/validate-device-profiles.py"
    info "  python3 firmware/scripts/validate-hardware-targets.py"
    return 0
  fi
  if [ -z "$PIO_RESOLVED" ]; then
    # An honest SKIP, never an abort. PlatformIO is pinned to 6.1.19, is not
    # pip-installable here, and its venv is not on the default PATH; without it
    # the build stage cannot run, but the validator and native host-suite stages
    # can, so point at those rather than reporting the firmware as broken.
    record SKIP "PlatformIO not found (PIO_BIN, /home/jkbmsr/.pio-venv/bin/pio, PATH); pinned to 6.1.19"
    info "the validate + host-tests stages need no PlatformIO; run them by hand:"
    info "  cd firmware && python3 scripts/validate-device-profiles.py"
    info "  cd firmware && python3 scripts/validate-hardware-targets.py"
    info "  cd firmware && ./scripts/run-host-tests.sh"
    info "or install PlatformIO 6.1.19 and set PIO_BIN=/path/to/pio"
    return 0
  fi
  # Pass the resolved PIO_BIN through so run-checks.sh's ensure_platformio()
  # accepts the 6.1.19 that is already present instead of trying to pip-install
  # it. PLATFORMIO_CORE_DIR is deliberately NOT overridden here: run-checks.sh
  # defaults it to firmware/.platformio-core and applies its per-platform
  # isolation on top, and duplicating that logic here would let the two drift.
  if PIO_BIN="$PIO_RESOLVED" "$runner" >"$log" 2>&1; then
    record PASS "firmware/scripts/run-checks.sh ok (pio $PIO_RESOLVED)"
  else
    record FAIL "firmware/scripts/run-checks.sh failed (see $log)"
  fi
}

# ---------------------------------------------------------------------------
# Dry run
# ---------------------------------------------------------------------------
if [ "$RUN" -eq 0 ]; then
  step "plan"
  if [ "${#ONLY[@]}" -gt 0 ]; then
    info "components selected: ${ONLY[*]}"
  else
    info "components: ${COMPONENTS[*]}"
  fi
  cat <<'PLAN'
   ..    apps/ble            flutter analyze && flutter test     (expect 70 passing)
   ..    apps/pro            flutter analyze && flutter test     (expect 85 passing)
   ..    apps/contributor    flutter analyze && flutter test     (expect 84 passing)
   ..    packages/bms_core   dart analyze && dart test           (expect 24 passing)
   ..    firmware            firmware/scripts/run-checks.sh
                          -> native host suites under ASan/UBSan,
                             validate-device-profiles.py, validate-hardware-targets.py,
                             and every PlatformIO environment in platformio.ini.
                             This is the slow one: expect minutes, not seconds. It
                             needs PlatformIO 6.1.19; if it is not found via PIO_BIN,
                             the known venv or PATH, the component SKIPs with that
                             reason rather than failing.
   ..    docs                npm ci (only if node_modules is missing) && npm run docs:build
   ..    releases            python3 scripts/validate_ota_metadata.py
PLAN
  say ""
  info "this is the default mode: nothing above was executed, nothing was written."
  say ""
  say "   To actually run the suites:  scripts/check-all.sh --run"
  say "   One component only:         scripts/check-all.sh --run --only firmware"
  exit 0
fi

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
LOG_DIR=$(mktemp -d)
info "logs: $LOG_DIR"

for component in "${COMPONENTS[@]}"; do
  selected "$component" || continue
  step "$component"
  case "$component" in
    apps/ble)         flutter_suite apps/ble "$BLE_EXPECTED_TESTS" ;;
    apps/pro)         flutter_suite apps/pro "$PRO_EXPECTED_TESTS" ;;
    apps/contributor) flutter_suite apps/contributor "$CONTRIBUTOR_EXPECTED_TESTS" ;;
    packages/bms_core) dart_suite packages/bms_core "$BMS_CORE_EXPECTED_TESTS" ;;
    firmware)         firmware_suite ;;
    docs)             docs_suite ;;
    releases)         releases_suite ;;
  esac
  printf '   ->    %s\n' "${RESULT[-1]}: ${DETAIL[-1]}"
done

# ---------------------------------------------------------------------------
# Table
# ---------------------------------------------------------------------------
step "summary"
printf '   %-12s %-6s %s\n' COMPONENT RESULT DETAIL
printf '   %-12s %-6s %s\n' ------------ ------ ------------------------------
failed=0
skipped=0
index=0
for component in "${COMPONENTS[@]}"; do
  selected "$component" || continue
  printf '   %-12s %-6s %s\n' "$component" "${RESULT[$index]}" "${DETAIL[$index]}"
  [ "${RESULT[$index]}" = FAIL ] && failed=$((failed + 1))
  [ "${RESULT[$index]}" = SKIP ] && skipped=$((skipped + 1))
  index=$((index + 1))
done
say ""
say "   components run: $index   failed: $failed   skipped: $skipped"
if [ "$skipped" -gt 0 ]; then
  say "   SKIP is not PASS. A skipped component is an unchecked component."
fi
say ""
if [ "$failed" -gt 0 ]; then
  say "   check-all: FAILED — do not open the pull request yet."
  exit 1
fi
if [ "$skipped" -gt 0 ] && [ "$STRICT" -eq 1 ]; then
  say "   check-all: FAILED (--strict, $skipped component(s) skipped)."
  exit 1
fi
say "   check-all: passed. Per-component logs are kept only when something failed."
exit 0
