#!/usr/bin/env bash
set -euo pipefail

missing=0

for tool in timeout curl python3 pio; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf 'ok   %s\n' "$tool"
  else
    printf 'miss %s\n' "$tool" >&2
    missing=1
  fi
done

serial_found=0
for candidate in /dev/ttyUSB* /dev/ttyACM*; do
  if [ -e "${candidate}" ]; then
    printf 'port %s\n' "${candidate}"
    serial_found=1
  fi
done

if [ "${serial_found}" -eq 0 ]; then
  echo "No USB ESP32 serial port detected" >&2
fi

echo "Smoke-test script: ./scripts/test-hardware-ota-smoke.sh"
echo "Claim-code API preflight: ./scripts/test-production-claim.sh"
echo "OTA API simulation script: ./scripts/test-production-ota.sh"

if [ "${missing}" -ne 0 ]; then
  exit 1
fi
