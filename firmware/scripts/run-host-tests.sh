#!/usr/bin/env bash
# Compile and actually EXECUTE the firmware unit suites on the host, under
# AddressSanitizer + UndefinedBehaviorSanitizer.
#
# Why this exists
# ---------------
# CI ran `pio test -e dev --without-uploading --without-testing`. The
# --without-testing flag skips execution, so every "[PASSED]" line in the logs
# was a *compile* result and the run summary read "0 test cases: 0 succeeded".
# No firmware unit test had ever actually run. That is not theoretical: it hid
# three real defects, all found the first time these suites executed —
#
#   * SeplosBmsDecoder checked the command byte at frame[3] (the fixed CID
#     0x46) instead of frame[4], rejecting every real device.
#   * The Seplos D2/Splos test fixture was two bytes short of its own declared
#     payload length, so the test asserting a successful parse could not fail.
#   * The Basen cell-chunk decoder used a radio-controlled length byte as a
#     cell count with no upper bound (out-of-bounds write), and Seplos used a
#     radio-controlled cell count as an array offset (out-of-bounds read).
#
# Most suites are pure decoders, but the list is not limited to them:
# test_provisioning covers ConfigStore, DeviceIdentity, the Improv Serial
# handshake and the SoftAP password derivation. Anything that would otherwise
# reach for WiFi.h, WebServer.h, DNSServer.h, Preferences.h or esp_random.h
# gets an inert stub in test/host/ instead.
#
# This script needs nothing but a host g++ and the shims in test/host/. It does
# not need PlatformIO, the ESP toolchain, or hardware.
#
# Usage:
#   scripts/run-host-tests.sh              # run every suite
#   scripts/run-host-tests.sh seplos basen # run suites whose dir name matches
#
# Exit status is non-zero if any suite fails to build or fails to run.

set -uo pipefail
cd "$(dirname "$0")/.."

HOST_INC=(-Itest/host -Iinclude -Isrc -Isrc/bms -Isrc/ota -Isrc/debug)
CXX=${CXX:-g++}
FLAGS=(-std=c++17 -g -O0 -fsanitize=address,undefined -fno-omit-frame-pointer -Wall)

# suite-name : source files needed to link it
SUITES=(
  "test_ant_bms_decoder:src/bms/AntBmsDecoder.cpp"
  "test_basen_bms_decoder:src/bms/BasenBmsDecoder.cpp"
  "test_daly_bms_parser:src/bms/DalyBmsParser.cpp:src/debug/DebugLog.cpp"
  "test_daly_d2_decoder:src/bms/DalyD2Decoder.cpp"
  "test_jbd_bms_parser:src/bms/JbdBmsParser.cpp:src/debug/DebugLog.cpp"
  "test_jk02_decoder:src/bms/Jk02Decoder.cpp"
  "test_jk_bms_parser:src/bms/JkBmsParser.cpp:src/debug/DebugLog.cpp"
  "test_ks_bms_decoder:src/bms/KsBmsDecoder.cpp"
  "test_lolan_bms_decoder:src/bms/LolanBmsDecoder.cpp"
  # Not decoder-only: this one covers the provisioning stack. The WiFi/WebServer/
  # DNSServer/Preferences/esp_random calls it links against are all inert shims
  # in test/host/, which is why it runs natively at all. ResetTrigger.cpp is
  # deliberately absent -- the suite only reads its constexpr hold windows, so
  # nothing from it is ODR-used and adding it would just drag pinMode()/
  # digitalRead() into the link for no extra coverage.
  "test_provisioning:src/config/ConfigStore.cpp:src/device/DeviceIdentity.cpp:src/provisioning/CaptivePortal.cpp:src/provisioning/ImprovProtocol.cpp:src/provisioning/ProvisioningManager.cpp"
  "test_seplos_ble_decoder:src/bms/SeplosBleDecoder.cpp"
  "test_tianpower_bms_decoder:src/bms/TianpowerBmsDecoder.cpp"
  "test_version_compare:src/ota/VersionCompare.cpp"
  # Pure Wi-Fi connect/retry/restart timing logic (src/network/WifiRetryPolicy.h
  # is header-only, so no extra source is needed).
  "test_wifi_retry"
)

# Every directory under test/ is listed in SUITES above, and the loop at the
# bottom fails the run if one ever is not. There is deliberately no
# "known-unportable" list any more: test_provisioning was skipped here for want
# of Preferences/LittleFS host stubs, and a suite that silently stops running is
# exactly the failure mode this script was written to kill — it is how three
# decoder defects survived, and how a stale app.jkbmsr.com onboarding-URL
# expectation sat in test_provisioning for 13 days after 7ca1737 retired that
# host. If a future suite cannot be ported, gate it in
# .github/workflows/firmware.yml by name instead of dropping it from SUITES.

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

declare -a FAILED_BUILD=() FAILED_RUN=() SKIPPED=()
passed=0

matches() {
  local name=$1; shift
  [ $# -eq 0 ] && return 0
  local pat
  for pat in "$@"; do
    [[ $name == *"$pat"* ]] && return 0
  done
  return 1
}

for entry in "${SUITES[@]}"; do
  IFS=':' read -r -a parts <<<"$entry"
  name=${parts[0]}
  sources=("${parts[@]:1}")

  if ! matches "$name" "$@"; then
    continue
  fi

  test_file="test/$name/test_main.cpp"
  if [ ! -f "$test_file" ]; then
    printf '%-28s SKIP   (no test_main.cpp)\n' "$name"
    SKIPPED+=("$name")
    continue
  fi

  if ! "$CXX" "${FLAGS[@]}" "${HOST_INC[@]}" \
        "$test_file" "${sources[@]}" test/host/host_main.cpp \
        -o "$OUT/$name" 2>"$OUT/$name.log"; then
    printf '%-28s BUILD-FAIL\n' "$name"
    grep -m2 -E 'error:' "$OUT/$name.log" | sed 's/^/       /'
    FAILED_BUILD+=("$name")
    continue
  fi

  if output=$("$OUT/$name" 2>&1); then
    summary=$(printf '%s\n' "$output" | grep -E '^[0-9]+ test' | tail -1)
    printf '%-28s PASS   %s\n' "$name" "$summary"
    passed=$((passed + 1))
  else
    summary=$(printf '%s\n' "$output" | grep -E '^[0-9]+ test' | tail -1)
    printf '%-28s FAIL   %s\n' "$name" "${summary:-no summary}"
    printf '%s\n' "$output" | grep -m5 'FAIL  (' | sed 's/^/       /'
    FAILED_RUN+=("$name")
  fi
done

# Guard against the failure mode this script exists to end: a test/ directory
# that is not in SUITES never runs, and nothing else in CI would say so — the
# PlatformIO "Compile tests" step does not execute, so an unlisted suite is
# indistinguishable from a passing one. Checked against the real directory
# listing, so adding a suite without wiring it here fails the job. Filtered runs
# only consider the suites they were asked for.
is_listed() {
  local want=$1 entry
  for entry in "${SUITES[@]}"; do
    [ "${entry%%:*}" = "$want" ] && return 0
  done
  return 1
}

while read -r dir; do
  [ -n "$dir" ] || continue
  matches "$dir" "$@" || continue
  is_listed "$dir" && continue
  printf '%-28s BUILD-FAIL  (test/%s exists but is not listed in SUITES)\n' "$dir" "$dir"
  FAILED_BUILD+=("$dir")
done < <(find test -mindepth 1 -maxdepth 1 -type d -name 'test_*' -printf '%f\n' | sort)

echo "----------------------------------------------------------------"
printf 'passed %d   build-fail %d   test-fail %d   skipped %d\n' \
  "$passed" "${#FAILED_BUILD[@]}" "${#FAILED_RUN[@]}" "${#SKIPPED[@]}"

[ "${#FAILED_BUILD[@]}" -eq 0 ] && [ "${#FAILED_RUN[@]}" -eq 0 ]
