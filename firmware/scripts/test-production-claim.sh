#!/usr/bin/env bash
# Machine-side production preflight for the claim-code path (no ESP32 required).
# Proves: device register with claimCode → user register → (optional verify) → claim → OTA.
#
# Production has email verification enabled. Full claim needs one of:
#   VERIFY_VIA_D1=1   (default) — mark the throwaway user verified via wrangler D1
#   VERIFIED_USER_TOKEN=… — use an already-verified customer JWT instead
#   SKIP_CLAIM=1 — stop after register + 403 enforcement check
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

API_BASE_URL="${API_BASE_URL:-https://api.jkbmsr.com}"
FIRMWARE_VERSION="${FIRMWARE_VERSION:-$(grep 'kFirmwareVersion' include/FirmwareVersion.h | sed -E 's/.*"([^"]+)".*/\1/')}"
DEVICE_ID="${DEVICE_ID:-sim-claim-$(date -u +%Y%m%d%H%M%S)}"
HARDWARE_ID="${HARDWARE_ID:-host-$(hostname)-$RANDOM}"
CLAIM_CODE="${CLAIM_CODE:-ABCD2345}"
USER_EMAIL="${USER_EMAIL:-claim-preflight-$(date -u +%Y%m%d%H%M%S)@example.com}"
USER_PASSWORD="${USER_PASSWORD:-preflight-pass-$((RANDOM))x}"
VERIFY_VIA_D1="${VERIFY_VIA_D1:-1}"
SKIP_CLAIM="${SKIP_CLAIM:-0}"
CLOUD_DIR="${CLOUD_DIR:-$(cd "${ROOT}/../jkbmsr-api" 2>/dev/null && pwd || true)}"

for tool in curl python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
done

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "== Production claim-code preflight =="
echo "API: ${API_BASE_URL}"
echo "Firmware version: ${FIRMWARE_VERSION}"
echo "Device ID: ${DEVICE_ID}"
echo "Claim code: ${CLAIM_CODE}"

register_payload="$(python3 - <<PY
import json
print(json.dumps({
  "deviceId": "${DEVICE_ID}",
  "hardwareId": "${HARDWARE_ID}",
  "firmwareVersion": "${FIRMWARE_VERSION}",
  "claimCode": "${CLAIM_CODE}",
}))
PY
)"

echo "1) Registering device with claimCode"
curl -fsS "${API_BASE_URL}/api/v1/device/register" \
  -H 'Content-Type: application/json' \
  -d "${register_payload}" > "${tmpdir}/register.json"

python3 - <<'PY' "${tmpdir}/register.json"
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
assert data.get("token"), "register response missing token"
assert data.get("deviceSecret"), "register response missing deviceSecret"
print("   device token ok; secret length", len(data["deviceSecret"]))
PY

if [ -n "${VERIFIED_USER_TOKEN:-}" ]; then
  user_token="${VERIFIED_USER_TOKEN}"
  echo "2) Using VERIFIED_USER_TOKEN from environment"
else
  echo "2) Creating throwaway user ${USER_EMAIL}"
  user_payload="$(python3 - <<PY
import json
print(json.dumps({
  "email": "${USER_EMAIL}",
  "password": "${USER_PASSWORD}",
}))
PY
)"
  curl -fsS "${API_BASE_URL}/api/v1/user/register" \
    -H 'Content-Type: application/json' \
    -d "${user_payload}" > "${tmpdir}/user.json"

  user_token="$(python3 - <<'PY' "${tmpdir}/user.json"
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
assert data.get("token"), "user register missing token"
print(data["token"])
PY
)"

  needs_verify="$(python3 - <<'PY' "${tmpdir}/user.json"
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
print("1" if data.get("emailVerificationRequired") else "0")
PY
)"

  if [ "${needs_verify}" = "1" ]; then
    echo "   email verification required in production"
    echo "3a) Confirming unverified claim is blocked (403)"
    claim_payload="$(python3 - <<PY
import json
print(json.dumps({"deviceId": "${DEVICE_ID}", "claimCode": "${CLAIM_CODE}"}))
PY
)"
    blocked_status="$(curl -sS -o "${tmpdir}/blocked.json" -w '%{http_code}' \
      "${API_BASE_URL}/api/v1/user/devices/claim" \
      -H "Authorization: Bearer ${user_token}" \
      -H 'Content-Type: application/json' \
      -d "${claim_payload}")"
    if [ "${blocked_status}" != "403" ]; then
      echo "Expected 403 before verify, got ${blocked_status}" >&2
      cat "${tmpdir}/blocked.json" >&2
      exit 1
    fi
    echo "   unverified claim blocked (403)"

    if [ "${SKIP_CLAIM}" = "1" ]; then
      echo "SKIP_CLAIM=1 — stopping after enforcement check"
      exit 0
    fi

    if [ "${VERIFY_VIA_D1}" != "1" ]; then
      echo "Set VERIFY_VIA_D1=1 or VERIFIED_USER_TOKEN to complete claim." >&2
      exit 1
    fi

    if [ -z "${CLOUD_DIR}" ] || [ ! -f "${CLOUD_DIR}/wrangler.jsonc" ]; then
      echo "jkbmsr-api not found next to firmware; set CLOUD_DIR=…" >&2
      exit 1
    fi

    echo "3b) Marking throwaway user verified via D1 (maintainer preflight)"
    (
      cd "${CLOUD_DIR}"
      # Load Cloudflare token if present in repo/infra env without printing secrets.
      if [ -f .env ]; then
        set -a
        # shellcheck disable=SC1091
        source .env
        set +a
      fi
      if [ -z "${CLOUDFLARE_API_TOKEN:-}" ] && [ -f ../jkbmsr-infra/.env ]; then
        set -a
        # shellcheck disable=SC1091
        source ../jkbmsr-infra/.env
        set +a
      fi
      npx wrangler d1 execute jkbmsr --remote --command \
        "UPDATE users SET email_verified = 1, verification_token = NULL, verification_expires_at = NULL, updated_at = datetime('now') WHERE email = '${USER_EMAIL}';"
    )
  else
    echo "   email verification not required"
  fi
fi

echo "4) Claiming with claimCode"
claim_payload="$(python3 - <<PY
import json
print(json.dumps({
  "deviceId": "${DEVICE_ID}",
  "claimCode": "${CLAIM_CODE}",
}))
PY
)"

claim_status="$(curl -sS -o "${tmpdir}/claim.json" -w '%{http_code}' \
  "${API_BASE_URL}/api/v1/user/devices/claim" \
  -H "Authorization: Bearer ${user_token}" \
  -H 'Content-Type: application/json' \
  -d "${claim_payload}")"

if [ "${claim_status}" != "200" ]; then
  echo "Claim failed HTTP ${claim_status}:" >&2
  cat "${tmpdir}/claim.json" >&2
  echo >&2
  exit 1
fi
echo "   claim ok"

echo "5) Rejecting wrong claim code on a fresh device"
BAD_DEVICE="sim-claim-bad-$(date -u +%Y%m%d%H%M%S)"
bad_register="$(python3 - <<PY
import json
print(json.dumps({
  "deviceId": "${BAD_DEVICE}",
  "hardwareId": "${HARDWARE_ID}-bad",
  "firmwareVersion": "${FIRMWARE_VERSION}",
  "claimCode": "GOODCODE1",
}))
PY
)"
curl -fsS "${API_BASE_URL}/api/v1/device/register" \
  -H 'Content-Type: application/json' \
  -d "${bad_register}" > /dev/null

bad_claim="$(python3 - <<PY
import json
print(json.dumps({
  "deviceId": "${BAD_DEVICE}",
  "claimCode": "WRONGXYZ1",
}))
PY
)"
bad_status="$(curl -sS -o "${tmpdir}/bad-claim.json" -w '%{http_code}' \
  "${API_BASE_URL}/api/v1/user/devices/claim" \
  -H "Authorization: Bearer ${user_token}" \
  -H 'Content-Type: application/json' \
  -d "${bad_claim}")"
if [ "${bad_status}" != "401" ]; then
  echo "Expected 401 for wrong claim code, got ${bad_status}" >&2
  cat "${tmpdir}/bad-claim.json" >&2
  exit 1
fi
echo "   wrong code rejected (401)"

echo "6) OTA metadata for registered device"
device_token="$(python3 - <<'PY' "${tmpdir}/register.json"
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    print(json.load(fh)["token"])
PY
)"
curl -fsS "${API_BASE_URL}/api/v1/ota/latest" \
  -H "Authorization: Bearer ${device_token}" > "${tmpdir}/ota.json"

python3 - <<'PY' "${tmpdir}/ota.json" "${FIRMWARE_VERSION}"
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
print("   updateAvailable:", data.get("updateAvailable"))
if data.get("version"):
    print("   offered version:", data.get("version"))
print("   device firmwareVersion at register:", sys.argv[2])
PY

echo
echo "Production claim-code preflight passed"
echo "Device ID: ${DEVICE_ID}"
echo "User: ${USER_EMAIL:-"(token)"}"
