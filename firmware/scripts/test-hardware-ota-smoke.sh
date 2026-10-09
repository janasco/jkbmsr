#!/usr/bin/env bash
set -euo pipefail

API_BASE_URL="${API_BASE_URL:-https://api.jkbmsr.com}"
SERIAL_PORT="${SERIAL_PORT:-}"
SERIAL_BAUD="${SERIAL_BAUD:-115200}"
CAPTURE_SECONDS="${CAPTURE_SECONDS:-15}"
FLASH_CURRENT_BUILD="${FLASH_CURRENT_BUILD:-1}"
DEVICE_ID="${DEVICE_ID:-}"
DEVICE_SECRET="${DEVICE_SECRET:-}"
DEVICE_TOKEN="${DEVICE_TOKEN:-}"

if ! command -v timeout >/dev/null 2>&1; then
  echo "Missing required tool: timeout" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Missing required tool: curl" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Missing required tool: python3" >&2
  exit 1
fi

if ! command -v pio >/dev/null 2>&1; then
  echo "Missing required tool: pio" >&2
  exit 1
fi

if [ -z "${SERIAL_PORT}" ]; then
  for candidate in /dev/ttyUSB* /dev/ttyACM*; do
    if [ -e "${candidate}" ]; then
      SERIAL_PORT="${candidate}"
      break
    fi
  done
fi

if [ -z "${SERIAL_PORT}" ]; then
  echo "No USB ESP32 serial port detected. Set SERIAL_PORT=/dev/ttyUSB0 or /dev/ttyACM0." >&2
  exit 1
fi

if [ "${FLASH_CURRENT_BUILD}" = "1" ]; then
  echo "Flashing current PlatformIO build to ${SERIAL_PORT}"
  pio run -t upload --upload-port "${SERIAL_PORT}"
else
  echo "Skipping firmware flash because FLASH_CURRENT_BUILD=${FLASH_CURRENT_BUILD}"
fi

boot_log_file="$(mktemp)"
trap 'rm -f "${boot_log_file}"' EXIT

echo "Capturing boot log from ${SERIAL_PORT} for ${CAPTURE_SECONDS}s"
set +e
timeout "${CAPTURE_SECONDS}"s pio device monitor --port "${SERIAL_PORT}" --baud "${SERIAL_BAUD}" > "${boot_log_file}" 2>&1
monitor_status=$?
set -e

if [ "${monitor_status}" -ne 0 ] && [ "${monitor_status}" -ne 124 ]; then
  cat "${boot_log_file}" >&2
  echo "Serial monitor failed" >&2
  exit "${monitor_status}"
fi

cat "${boot_log_file}"

if ! grep -q "JKBMSR firmware starting" "${boot_log_file}"; then
  echo "Boot log did not show the expected startup banner" >&2
  exit 1
fi

echo "Boot log banner verified"

if [ -z "${DEVICE_TOKEN}" ] && [ -n "${DEVICE_ID}" ] && [ -n "${DEVICE_SECRET}" ]; then
  login_payload="$(python3 - <<PY
import json
print(json.dumps({
  "deviceId": "${DEVICE_ID}",
  "deviceSecret": "${DEVICE_SECRET}",
}))
PY
)"

  echo "Logging the flashed device into ${API_BASE_URL}"
  login_response="$(curl -fsS "${API_BASE_URL}/v1/device/login" -H 'Content-Type: application/json' -d "${login_payload}")"
  DEVICE_TOKEN="$(python3 - <<'PY' "${login_response}"
import json
import sys
print(json.loads(sys.argv[1])["token"])
PY
)"
fi

if [ -n "${DEVICE_TOKEN}" ]; then
  echo "Polling live OTA metadata for the flashed device"
  ota_response="$(curl -fsS "${API_BASE_URL}/v1/ota/latest" -H "Authorization: Bearer ${DEVICE_TOKEN}")"
  printf '%s\n' "${ota_response}"
else
  echo "Skipping OTA poll because DEVICE_TOKEN or DEVICE_ID+DEVICE_SECRET was not provided"
  echo "Use this after the board has already registered or logged in once."
fi
