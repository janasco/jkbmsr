#!/usr/bin/env bash
# Generate a *development-only* Secure Boot v2 signing key for env:idf-secureboot.
# Never commit the PEM. Never reuse this key as the OTA metadata signing key.
# Production Secure Boot keys are a Phase 3 / manufacturing concern.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY_DIR="${ROOT}/keys"
KEY_PATH="${KEY_DIR}/secure_boot_signing_key.pem"

mkdir -p "${KEY_DIR}"

if [[ -f "${KEY_PATH}" ]]; then
  echo "Key already exists: ${KEY_PATH}"
  echo "Delete it first if you intentionally want to rotate the *dev* key."
  exit 0
fi

# Secure Boot v2's key requirement is just a standard RSA-3072 private key
# in traditional PKCS#1 PEM form -- generate it with openssl (present on
# every dev machine and CI runner already) instead of the vendored
# espsecure.py CLI. That script's CLI arg structure and import chain
# (rich_click, cryptography, ecdsa, pyserial, intelhex, ...) depend on
# exactly which tool-esptoolpy version happens to be installed, which
# drifts since platform = espressif32 is unpinned in platformio.ini --
# this sidesteps that whole moving target. Verified: a build signed with
# an openssl-generated key here produces an identical, working signed
# image via `pio run -e idf-secureboot*` (2026-08-21).
openssl genrsa -traditional -out "${KEY_PATH}" 3072
chmod 600 "${KEY_PATH}"

echo "Wrote ${KEY_PATH}"
echo "Build with: pio run -e idf-secureboot"
echo "Remember: ESP32 ECO3+ only; keep this PEM out of git."
