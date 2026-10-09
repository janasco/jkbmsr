#!/usr/bin/env bash
set -euo pipefail

API_BASE_URL="${API_BASE_URL:-https://api.jkbmsr.com}"
FIRMWARE_VERSION="${FIRMWARE_VERSION:-$(grep 'kFirmwareVersion' include/FirmwareVersion.h | sed -E 's/.*"([^"]+)".*/\1/')}"
DEVICE_ID="${DEVICE_ID:-sim-ota-$(date -u +%Y%m%d%H%M%S)}"
HARDWARE_ID="${HARDWARE_ID:-host-$(hostname)-$RANDOM}"
PUBLIC_KEY_PATH="${PUBLIC_KEY_PATH:-docs/ota-signing-public-key.pem}"

for tool in curl python3 openssl sha256sum; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
done

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

register_payload="$(python3 - <<PY
import json
print(json.dumps({
  "deviceId": "${DEVICE_ID}",
  "hardwareId": "${HARDWARE_ID}",
  "firmwareVersion": "${FIRMWARE_VERSION}",
  "claimCode": "OTA-TEST1",
}))
PY
)"

echo "Registering simulated device ${DEVICE_ID} against ${API_BASE_URL}"
register_response="$(curl -fsS "${API_BASE_URL}/v1/device/register" -H 'Content-Type: application/json' -d "${register_payload}")"
printf '%s' "${register_response}" > "${tmpdir}/register.json"

device_token="$(python3 - <<'PY' "${tmpdir}/register.json"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data["token"])
PY
)"

device_secret="$(python3 - <<'PY' "${tmpdir}/register.json"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data["deviceSecret"])
PY
)"

echo "Registered device secret length: ${#device_secret}"
echo "Requesting live OTA metadata"
ota_response="$(curl -fsS "${API_BASE_URL}/v1/ota/latest" -H "Authorization: Bearer ${device_token}")"
printf '%s' "${ota_response}" > "${tmpdir}/ota.json"

python3 - <<'PY' "${tmpdir}/ota.json"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(json.dumps(data, indent=2))
PY

update_available="$(python3 - <<'PY' "${tmpdir}/ota.json"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
print("true" if data.get("updateAvailable") else "false")
PY
)"

if [ "${update_available}" != "true" ]; then
  echo "No OTA update available for simulated device"
  exit 0
fi

download_url="$(python3 - <<'PY' "${tmpdir}/ota.json"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data["downloadUrl"])
PY
)"

version="$(python3 - <<'PY' "${tmpdir}/ota.json"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data["version"])
PY
)"

target_hardware="$(python3 - <<'PY' "${tmpdir}/ota.json"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data["targetHardware"])
PY
)"

released_at="$(python3 - <<'PY' "${tmpdir}/ota.json"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data["releasedAt"])
PY
)"

expected_sha256="$(python3 - <<'PY' "${tmpdir}/ota.json"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data["sha256"])
PY
)"

signature="$(python3 - <<'PY' "${tmpdir}/ota.json"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data["signature"])
PY
)"

signing_key_id="$(python3 - <<'PY' "${tmpdir}/ota.json"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data["signingKeyId"])
PY
)"

signature_algorithm="$(python3 - <<'PY' "${tmpdir}/ota.json"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data["signatureAlgorithm"])
PY
)"

printf '%s\n%s\n%s\n%s' "${version}" "${target_hardware}" "${released_at}" "${expected_sha256}" > "${tmpdir}/payload.txt"
printf '%s' "${signature}" | base64 -d > "${tmpdir}/signature.bin"

echo "Verifying OTA metadata signature"
openssl dgst -sha256 -verify "${PUBLIC_KEY_PATH}" -signature "${tmpdir}/signature.bin" "${tmpdir}/payload.txt"

echo "Downloading firmware artifact"
curl -fsS "${download_url}" -H "Authorization: Bearer ${device_token}" -o "${tmpdir}/firmware.bin"

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
