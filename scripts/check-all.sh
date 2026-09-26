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
#   apps/ble    flutter analyze && flutter test          (expect 70 passing)
#   apps/pro    flutter analyze && flutter test          (expect 85 passing)
#   firmware    native host suites under ASan/UBSan, plus the device-profile
#               and hardware-target validators — see firmware/scripts/run-checks.sh
#   docs        npm run docs:build
#   releases    python3 scripts/validate_release_index.py
#
# Usage:
#   scripts/check-all.sh                 # dry run: print every command, run nothing
#   scripts/check-all.sh --run           # run every suite, print a pass/fail table
#   scripts/check-all.sh --run --only docs --only releases
#
# Options:
#   --run          Actually execute the suites. Without it nothing is executed.
#   --only NAME    Restrict to a component (apps/ble, apps/pro, firmware, docs,
#                  releases). Repeatable. Implies nothing about running: still
#                  needs --run.
#   --strict       Treat a skipped component as a failure. Use it when you are
#                  the last person before a merge and a green table that skipped
#                  half the tree is worse than no table.
#   -h, --help     This text.
#
# Environment:
#   FLUTTER_BIN              directory to prepend to PATH (default
#                            /home/jkbmsr/flutter/bin, prepended only if it exists
#                            and flutter is not already on PATH)
#   BLE_EXPECTED_TESTS       expected passing test count for apps/ble (default 70)
#   PRO_EXPECTED_TESTS       expected passing test count for apps/pro (default 85)
#
# Exit status: 0 everything that ran passed (skips are allowed unless --strict),
# 1 at least one component failed, 2 usage error.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

COMPONENTS=(apps/ble apps/pro firmware docs releases)

RUN=0
STRICT=0
ONLY=()
BLE_EXPECTED_TESTS=${BLE_EXPECTED_TESTS:-70}
PRO_EXPECTED_TESTS=${PRO_EXPECTED_TESTS:-85}
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
if command -v pio >/dev/null 2>&1; then
  ok "pio ($(pio --version 2>&1 | head -1))"
else
  warn "pio not found — the firmware suite builds 25 PlatformIO environments and needs 6.1.19"
fi
if command -v flutter >/dev/null 2>&1; then
  ok "flutter ($(command -v flutter))"
else
  warn "flutter not found — apps/ble and apps/pro cannot be checked."
  warn "  add it with: export PATH=\$PATH:${FLUTTER_BIN:-/home/jkbmsr/flutter/bin}"
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
  if [ ! -f "$releases_dir/scripts/validate_release_index.py" ]; then
    record SKIP "validate_release_index.py not found"
    return 0
  fi
  if ( cd "$releases_dir" && python3 scripts/validate_release_index.py ) >"$log" 2>&1; then
    record PASS "release index consistent"
  else
    record FAIL "validate_release_index.py failed (see $log)"
  fi
}

firmware_suite() {
  local log="$LOG_DIR/firmware.log"
  local runner="$REPO_ROOT/firmware/scripts/run-checks.sh"
  if [ -x "$runner" ]; then
    if "$runner" >"$log" 2>&1; then
      record PASS "firmware/scripts/run-checks.sh ok"
    else
      record FAIL "firmware/scripts/run-checks.sh failed (see $log)"
    fi
    return 0
  fi
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
   ..    apps/ble     flutter analyze && flutter test     (expect 70 passing)
   ..    apps/pro     flutter analyze && flutter test     (expect 85 passing)
   ..    firmware     firmware/scripts/run-checks.sh
                    -> native host suites under ASan/UBSan,
                       validate-device-profiles.py, validate-hardware-targets.py,
                       and every PlatformIO environment in platformio.ini.
                       This is the slow one: expect minutes, not seconds, and
                       it needs PlatformIO 6.1.19.
   ..    docs         npm ci (only if node_modules is missing) && npm run docs:build
   ..    releases     python3 scripts/validate_release_index.py
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
    apps/ble)  flutter_suite apps/ble "$BLE_EXPECTED_TESTS" ;;
    apps/pro)  flutter_suite apps/pro "$PRO_EXPECTED_TESTS" ;;
    firmware)  firmware_suite ;;
    docs)      docs_suite ;;
    releases)  releases_suite ;;
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
