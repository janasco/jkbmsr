#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Production OTA smoke test.
#
# Registers a throwaway simulated gateway against the live API, asks it for its
# OTA metadata, verifies the ECDSA signature and the firmware checksum, then
# removes the simulated device again. It is a read-only probe of the production
# OTA path: it downloads and checks, it never flashes or publishes.
#
# Usage:
#   ./scripts/test-production-ota.sh
#   FIRMWARE_VERSION=0.0.0 TARGET_HARDWARE=esp32-classic-4mb ./scripts/test-production-ota.sh
#   ./scripts/test-production-ota.sh --keep     # leave the simulated device (debugging)
#
# Cleanup needs Cloudflare credentials (CLOUDFLARE_API_TOKEN and the account id
# below); without them the script refuses to run rather than leak a device row.
# See the cleanup section for why deletion cannot go through the device API.
# ---------------------------------------------------------------------------

set -euo pipefail

API_BASE_URL="${API_BASE_URL:-https://api.jkbmsr.com}"
FIRMWARE_VERSION="${FIRMWARE_VERSION:-$(grep 'kFirmwareVersion' include/FirmwareVersion.h | sed -E 's/.*"([^"]+)".*/\1/')}"
# A real gateway reports the hardware it is actually running, and the API only
# serves OTA metadata for a known target. esp32-classic-4mb is the mainstream
# ESP32 target; override it to exercise another one.
TARGET_HARDWARE="${TARGET_HARDWARE:-esp32-classic-4mb}"
HARDWARE_PLATFORM="${HARDWARE_PLATFORM:-esp32}"
# The target is part of the id so a leftover row (see --keep) says which target
# it was probing at a glance.
DEVICE_ID="${DEVICE_ID:-sim-ota-$(date -u +%Y%m%d%H%M%S)-${TARGET_HARDWARE}}"
HARDWARE_ID="${HARDWARE_ID:-host-$(hostname)-$RANDOM}"
PUBLIC_KEY_PATH="${PUBLIC_KEY_PATH:-docs/ota-signing-public-key.pem}"

# Fixed infrastructure identifiers, mirroring scripts/release.sh. Deliberately
# constants, not env-overridable defaults: the API token can see the
# pre-migration and current Cloudflare accounts, and both have a D1 database
# named `jkbmsr`, so an unasserted delete could land in the wrong one.
JKBMSR_CLOUDFLARE_ACCOUNT_ID="9c686ab673caa0f69af5bee930392670"
D1_DATABASE="jkbmsr"
WRANGLER_VERSION="4.118.0"
# Never float to the newest published wrangler: a moving tag is how a publish
# or cleanup path breaks without this repository changing.

KEEP_DEVICE=0
REGISTERED=0
DEVICE_DELETE_ATTEMPTED=0

for arg in "$@"; do
  case "$arg" in
    --keep) KEEP_DEVICE=1 ;;
    -h | --help)
      sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done

for tool in python3 openssl sha256sum; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
done

# Cleanup is mandatory unless the operator explicitly asks to keep the device.
# Prove it can run up front, so a missing credential can never leak a row
# half-way through the test.
if [ "$KEEP_DEVICE" -eq 0 ]; then
  if [ -z "${CLOUDFLARE_API_TOKEN:-}" ] || [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
    cat >&2 <<MSG

  Refusing to start: cleanup needs CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID,
  and there is no device-auth delete endpoint for the API to fall back on.
  Without them the simulated device would be left in the devices table.
  Export both (provenance: jkbmsr-private/backend/.env), or pass --keep to leave
  the device deliberately.
MSG
    exit 1
  fi
  if [ "$CLOUDFLARE_ACCOUNT_ID" != "$JKBMSR_CLOUDFLARE_ACCOUNT_ID" ]; then
    echo "Refusing to start: CLOUDFLARE_ACCOUNT_ID is '${CLOUDFLARE_ACCOUNT_ID}', expected '${JKBMSR_CLOUDFLARE_ACCOUNT_ID}' -- the token can see two accounts with a same-named ${D1_DATABASE} database." >&2
    exit 1
  fi
fi

tmpdir="$(mktemp -d)"

# ── HTTP via Python, never curl ─────────────────────────────────────────────
# curl is broken on this host -- it errors out with "ORDER: parameter null or
# not set" before sending anything -- so every HTTP call here goes through
# Python's urllib instead. This is the same pattern scripts/release.sh uses,
# where curl is deliberately banned for the same reason.
#
# http_request <method> <url> <outfile> [--data <file>] [--header "Name: value"]...
http_request() {
  local method="$1" url="$2" out="$3"
  shift 3
  python3 - "$method" "$url" "$out" "$@" <<'PY'
import sys
import urllib.error
import urllib.request

method, url, out = sys.argv[1], sys.argv[2], sys.argv[3]
headers = {}
data = None
args = sys.argv[4:]
i = 0
while i < len(args):
    if args[i] == "--header":
        name, _, value = args[i + 1].partition(":")
        headers[name.strip()] = value.strip()
        i += 2
    elif args[i] == "--data":
        with open(args[i + 1], "rb") as fh:
            data = fh.read()
        i += 2
    else:
        sys.stderr.write(f"http_request: unknown argument {args[i]}\n")
        sys.exit(2)

# Cloudflare's edge answers the default Python-urllib User-Agent with
# "error code: 1010" (HTTP 403) -- a bot check, not a missing endpoint. An
# explicit, non-default UA passes; callers can still override it.
headers.setdefault("User-Agent", "jkbmsr-ota-selftest/1.0")

request = urllib.request.Request(url, data=data, headers=headers, method=method)
try:
    with urllib.request.urlopen(request, timeout=60) as response:
        body = response.read()
except urllib.error.HTTPError as error:
    detail = error.read().decode("utf-8", "replace").strip()
    sys.stderr.write(f"HTTP {error.code} {method} {url}: {detail}\n")
    sys.exit(1)
except urllib.error.URLError as error:
    sys.stderr.write(f"{method} {url} failed: {error.reason}\n")
    sys.exit(1)

with open(out, "wb") as fh:
    fh.write(body)
PY
}

json_field() {
  # json_field <file> <key> -- prints the value, or nothing if absent.
  python3 - "$1" "$2" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
value = data.get(sys.argv[2])
if value is not None:
    print(value)
PY
}

# ── Cleanup ─────────────────────────────────────────────────────────────────
# There is NO device-auth delete endpoint. The device API exposes register,
# login, config, ota/status and wifi/status only; deletion lives on the
# account-authenticated DELETE /v1/dashboard/devices/:deviceId (owner only) and
# the admin DELETE /v1/admin/devices/:deviceId. Both require a user JWT that a
# device-simulation script does not have, and the owner route additionally
# cannot see an unclaimed device at all.
#
# So cleanup goes straight at D1 over the same REST path wrangler uses,
# replaying the exact cascade the two API delete routes run
# (backend/src/services/devices.ts deleteDeviceCascade). The account id is
# asserted first, because the token can see two accounts that both have a D1
# database named `jkbmsr`.
assert_safe_identifier() {
  local value="$1" label="$2"
  printf '%s' "$value" | grep -Eq '^[A-Za-z0-9._-]+$' \
    || { echo "Refusing to build SQL: ${label} value '${value}' contains unsupported characters" >&2; return 1; }
}

delete_simulated_device() {
  [ "$REGISTERED" -eq 1 ] || return 0
  if [ "$KEEP_DEVICE" -eq 1 ]; then
    echo "Cleanup skipped (--keep): ${DEVICE_ID} left in the devices table." >&2
    return 0
  fi
  [ "$DEVICE_DELETE_ATTEMPTED" -eq 0 ] || return 0
  DEVICE_DELETE_ATTEMPTED=1

  echo "Removing simulated device ${DEVICE_ID}"
  assert_safe_identifier "$DEVICE_ID" "device id" || return 1

  if [ -z "${CLOUDFLARE_API_TOKEN:-}" ] || [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
    cat >&2 <<MSG

  Cannot remove ${DEVICE_ID}: CLOUDFLARE_API_TOKEN and/or CLOUDFLARE_ACCOUNT_ID
  are unset, and there is no device-auth delete endpoint to fall back on. The
  device row would be leaked, so this is a failure rather than a warning.
  Export both (provenance: jkbmsr-private/backend/.env) and re-run, or pass
  --keep to leave the device deliberately.
MSG
    return 1
  fi
  if [ "$CLOUDFLARE_ACCOUNT_ID" != "$JKBMSR_CLOUDFLARE_ACCOUNT_ID" ]; then
    echo "  CLOUDFLARE_ACCOUNT_ID is '${CLOUDFLARE_ACCOUNT_ID}', expected '${JKBMSR_CLOUDFLARE_ACCOUNT_ID}' -- refusing to delete from the wrong account" >&2
    return 1
  fi
  command -v npx >/dev/null 2>&1 || { echo "  npx is required to reach D1 for cleanup" >&2; return 1; }

  local sql
  sql=$(cat <<SQL
DELETE FROM telemetry WHERE device_id = '${DEVICE_ID}';
DELETE FROM alerts WHERE device_id = '${DEVICE_ID}';
DELETE FROM ota_events WHERE device_id = '${DEVICE_ID}';
DELETE FROM device_configs WHERE device_id = '${DEVICE_ID}';
DELETE FROM device_wifi_configs WHERE device_id = '${DEVICE_ID}';
DELETE FROM device_shares WHERE device_id = '${DEVICE_ID}';
DELETE FROM devices WHERE device_id = '${DEVICE_ID}';
SQL
)
  npx --yes "wrangler@${WRANGLER_VERSION}" d1 execute "$D1_DATABASE" --remote \
    --command "$sql" >"${tmpdir}/cleanup.log" 2>&1 || {
    echo "  D1 cleanup command failed:" >&2
    sed 's/^/    /' "${tmpdir}/cleanup.log" >&2
    return 1
  }
  echo "  removed ${DEVICE_ID} (and its device_configs) from D1 ${D1_DATABASE}"
}

cleanup() {
  local status=$?
  trap - EXIT
  if ! delete_simulated_device; then
    echo "cleanup: FAILED to remove ${DEVICE_ID} from the devices table." >&2
    if [ "$status" -eq 0 ]; then
      status=1
    fi
  fi
  if [ -n "${tmpdir:-}" ] && [ -d "$tmpdir" ]; then
    rm -rf "$tmpdir"
  fi
  exit "$status"
}
trap cleanup EXIT

# ── Register ────────────────────────────────────────────────────────────────
echo "Registering simulated device ${DEVICE_ID} against ${API_BASE_URL}"
python3 - "${DEVICE_ID}" "${HARDWARE_ID}" "${FIRMWARE_VERSION}" "${TARGET_HARDWARE}" "${HARDWARE_PLATFORM}" > "${tmpdir}/register-payload.json" <<'PY'
import json, sys
device_id, hardware_id, firmware_version, target_hardware, hardware_platform = sys.argv[1:6]
print(json.dumps({
    "deviceId": device_id,
    "hardwareId": hardware_id,
    "firmwareVersion": firmware_version,
    "targetHardware": target_hardware,
    "hardwarePlatform": hardware_platform,
    "claimCode": "OTA-TEST1",
}))
PY

http_request POST "${API_BASE_URL}/v1/device/register" "${tmpdir}/register.json" \
  --header "Content-Type: application/json" \
  --data "${tmpdir}/register-payload.json"
REGISTERED=1

device_token="$(json_field "${tmpdir}/register.json" token)"
device_secret="$(json_field "${tmpdir}/register.json" deviceSecret)"

echo "Registered device secret length: ${#device_secret}"
echo "Requesting live OTA metadata"
http_request GET "${API_BASE_URL}/v1/ota/latest" "${tmpdir}/ota.json" \
  --header "Authorization: Bearer ${device_token}"

python3 - "${tmpdir}/ota.json" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(json.dumps(data, indent=2))
PY

update_available="$(python3 - "${tmpdir}/ota.json" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
print("true" if data.get("updateAvailable") else "false")
PY
)"

if [ "${update_available}" != "true" ]; then
  echo "No OTA update available for simulated device (reported version ${FIRMWARE_VERSION} on ${TARGET_HARDWARE})"
  exit 0
fi

download_url="$(json_field "${tmpdir}/ota.json" downloadUrl)"
version="$(json_field "${tmpdir}/ota.json" version)"
target_hardware="$(json_field "${tmpdir}/ota.json" targetHardware)"
released_at="$(json_field "${tmpdir}/ota.json" releasedAt)"
expected_sha256="$(json_field "${tmpdir}/ota.json" sha256)"
signature="$(json_field "${tmpdir}/ota.json" signature)"
signing_key_id="$(json_field "${tmpdir}/ota.json" signingKeyId)"
signature_algorithm="$(json_field "${tmpdir}/ota.json" signatureAlgorithm)"

printf '%s\n%s\n%s\n%s' "${version}" "${target_hardware}" "${released_at}" "${expected_sha256}" > "${tmpdir}/payload.txt"
printf '%s' "${signature}" | base64 -d > "${tmpdir}/signature.bin"

echo "Verifying OTA metadata signature"
openssl dgst -sha256 -verify "${PUBLIC_KEY_PATH}" -signature "${tmpdir}/signature.bin" "${tmpdir}/payload.txt"

echo "Downloading firmware artifact"
http_request GET "${download_url}" "${tmpdir}/firmware.bin" \
  --header "Authorization: Bearer ${device_token}"

actual_sha256="$(sha256sum "${tmpdir}/firmware.bin" | awk '{print $1}')"
if [ "${actual_sha256}" != "${expected_sha256}" ]; then
  echo "Firmware checksum mismatch" >&2
  echo "Expected: ${expected_sha256}" >&2
  echo "Actual:   ${actual_sha256}" >&2
  exit 1
fi

echo "Production OTA simulation passed"
echo "Device ID: ${DEVICE_ID}"
echo "Release version: ${version}"
echo "Signing key ID: ${signing_key_id}"
echo "Signature algorithm: ${signature_algorithm}"
echo "Checksum: ${actual_sha256}"
