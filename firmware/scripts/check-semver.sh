#!/usr/bin/env bash
# Validate a version string using the FIRMWARE'S OWN isValidSemver().
#
# Why not a regex in bash: src/ota/VersionCompare.cpp already defines what this
# project means by a version -- it is the same function the device's OTA
# anti-rollback floor is checked against, and the same one test_version_compare
# asserts on. A release script that reimplemented the rule would be a second
# source of truth that can drift from the firmware. This compiles the real
# implementation against the host shims in test/host/ (the same approach, and
# the same -I set, as scripts/run-host-tests.sh) and asks it.
#
# Usage:
#   scripts/check-semver.sh <version>            # firmware's isValidSemver()
#   scripts/check-semver.sh --strict <version>   # + the release-sink rules
#   scripts/check-semver.sh --quiet <version>    # exit status only
#
# Exit status:
#   0  valid   1  invalid   2  usage / build error
#
# ── Why --strict exists, and why both checks are required ─────────────────────
# isValidSemver() deliberately accepts more than a bare release version: it
# trims surrounding whitespace and tolerates a leading "v" and a "-prerelease"
# suffix, because a device must be able to *parse* whatever a stored config
# happens to contain (see the note on isValidSemver() in VersionCompare.h about
# repairing a corrupt floor).
#
# That leniency is wrong for a release tag. The release version is
# interpolated into, among other things:
#
#   * a D1 SQL statement as a single-quoted literal,
#   * an R2 object key and a directory name (v<version>/),
#   * a GitHub tag (firmware-v<version>) and release asset names.
#
# The old CI release job therefore required a strict MAJOR.MINOR.PATCH and
# failed the release on anything else, with the comment "require a strict
# MAJOR.MINOR.PATCH so a malformed or unexpected string (quotes, SQL
# metacharacters, whitespace) can never flow into those sinks -- fail the
# release instead." Both gates are kept: isValidSemver() proves the firmware
# itself would accept the string, and --strict proves it is safe to write into
# the sinks.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ROOT}/scripts/semver-check.cpp"
VERSION_COMPARE="${ROOT}/src/ota/VersionCompare.cpp"

# Keep the shim/toolchain cache inside the repository's own gitignored
# directories so a hand-run check never litters a developer's home directory
# and never shows up as an untracked file.
CACHE_DIR="${ROOT}/.platformio-core/semver-check"
BIN="${CACHE_DIR}/semver-check"

STRICT=0
QUIET=0

usage() {
  sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'check-semver: %s\n' "$1" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1 ;;
    --quiet | -q) QUIET=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    --) shift; break ;;
    -*) die "unknown option: $1 (try --help)" ;;
    *) break ;;
  esac
  shift
done

[ $# -eq 1 ] || die "expected exactly one version argument (try --help)"
VERSION="$1"

[ -f "$SRC" ] || die "missing $SRC"
[ -f "$VERSION_COMPARE" ] || die "missing $VERSION_COMPARE"

CXX="${CXX:-g++}"
command -v "$CXX" >/dev/null 2>&1 || die "no C++ compiler found (need g++; set CXX to override)"

# Rebuild only when the harness, the implementation, or a shim header is newer
# than the cached binary. Rebuilding on every release is a waste of the one
# step here that actually costs something.
if [ ! -x "$BIN" ] || [ "$SRC" -nt "$BIN" ] || [ "$VERSION_COMPARE" -nt "$BIN" ] \
  || [ -n "$(find "$ROOT/test/host" -name '*.h' -newer "$BIN" -print -quit 2>/dev/null)" ]; then
  mkdir -p "$CACHE_DIR"
  # Same include set as run-host-tests.sh: test/host supplies the inert
  # Arduino/WiFi/etc. shims, src/ota holds VersionCompare.
  "$CXX" -std=c++17 -O0 -Wall \
    -I"${ROOT}/test/host" -I"${ROOT}/include" -I"${ROOT}/src" \
    -I"${ROOT}/src/bms" -I"${ROOT}/src/ota" -I"${ROOT}/src/debug" \
    "$SRC" "$VERSION_COMPARE" -o "$BIN"
fi

RESULT="$("$BIN" "$VERSION")"

[ "$QUIET" -eq 1 ] || printf '%s is %s semver\n' "$VERSION" "$RESULT"

if [ "$RESULT" != "valid" ]; then
  exit 1
fi

if [ "$STRICT" -eq 1 ] && ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  [ "$QUIET" -eq 1 ] || printf '%s is not a strict MAJOR.MINOR.PATCH (leading "v", prerelease suffix and surrounding whitespace are all rejected here -- see the --strict note in this script)\n' "$VERSION" >&2
  exit 1
fi

exit 0
