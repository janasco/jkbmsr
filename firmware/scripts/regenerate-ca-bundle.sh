#!/usr/bin/env bash
#
# Regenerate the embedded TLS root-CA bundle used by the firmware to verify
# api.jkbmsr.com (and any other first-party HTTPS host it talks to).
#
# The device validates the server certificate chain against these roots, the
# same way a browser does. This is what makes setInsecure() unnecessary — see
# src/net/SecureClient.cpp.
#
# Source of trust: Mozilla's CA list, as exported and published by the curl
# project (https://curl.se/docs/caextract.html), plus the pinned extra roots
# in data/cert/extra-roots.pem (roots Mozilla has retired that production
# chains still require — see that file for provenance). We commit both the
# source PEM (data/cert/cacert.pem, human-auditable) and the generated indexed
# binary (data/cert/x509_crt_bundle.bin, what actually gets embedded) so
# builds are self-contained and the provenance is reviewable in git history.
#
# When to run this:
#   - Periodically, to pick up Mozilla root additions/removals.
#   - Urgently, if devices start failing TLS after a Cloudflare CA change and
#     the new root is not yet in the committed bundle.
#
# Requirements: python3 with the `cryptography` package installed, plus curl
# and openssl.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_DIR="${REPO_ROOT}/data/cert"
GEN="${REPO_ROOT}/scripts/gen_crt_bundle.py"

echo "Fetching current Mozilla CA bundle from curl.se..."
curl -fsSL "https://curl.se/ca/cacert.pem" -o "${CERT_DIR}/cacert.pem"

mozilla_count="$(grep -c 'BEGIN CERTIFICATE' "${CERT_DIR}/cacert.pem")"
echo "Downloaded ${mozilla_count} Mozilla root certificates."

echo "Appending pinned extra roots (data/cert/extra-roots.pem)..."
cat "${CERT_DIR}/extra-roots.pem" >> "${CERT_DIR}/cacert.pem"

count="$(grep -c 'BEGIN CERTIFICATE' "${CERT_DIR}/cacert.pem")"
echo "Bundle now holds ${count} root certificates."

echo "Generating indexed bundle..."
( cd "${CERT_DIR}" && python3 "${GEN}" --input cacert.pem && mv x509_crt_bundle x509_crt_bundle.bin )

echo "Done. Updated:"
echo "  ${CERT_DIR}/cacert.pem"
echo "  ${CERT_DIR}/x509_crt_bundle.bin ($(wc -c < "${CERT_DIR}/x509_crt_bundle.bin") bytes)"
echo
echo "Checking the production host validates the way the DEVICE does..."
"${REPO_ROOT}/scripts/verify-device-trust.sh" api.jkbmsr.com "${CERT_DIR}/cacert.pem"
