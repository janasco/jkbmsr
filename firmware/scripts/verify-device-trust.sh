#!/usr/bin/env bash
#
# Verify a TLS host's certificate chain the way the ESP32 firmware does.
#
# The device uses ESP-IDF's esp_crt_bundle (Arduino core / IDF 4.4), whose
# verify callback trusts a chain only if the TOP certificate the server
# PRESENTS has its ISSUER's subject+key in the embedded bundle. That is
# stricter than desktop OpenSSL, which also accepts a chain when any presented
# cert's subject+key matches a trust anchor (so `openssl verify` / `s_client
# -CAfile` can say OK while the device fails — this happened with the
# GTS Root R4 cross-signed by GlobalSign Root CA chain in July 2026).
#
# Usage: verify-device-trust.sh <host> <ca-bundle.pem>
#
set -euo pipefail

host="${1:?usage: verify-device-trust.sh <host> <ca-bundle.pem>}"
bundle="${2:?usage: verify-device-trust.sh <host> <ca-bundle.pem>}"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo | openssl s_client -connect "${host}:443" -servername "$host" -showcerts 2>/dev/null |
  awk -v dir="$workdir" '/BEGIN CERTIFICATE/{n++; f=dir "/chain-" n ".pem"} f{print > f} /END CERTIFICATE/{f=""}'

top="$(ls "$workdir"/chain-*.pem | sort -t- -k2 -n | tail -1)"
top_subject="$(openssl x509 -in "$top" -noout -subject)"
top_issuer="$(openssl x509 -in "$top" -noout -issuer)"
echo "Top presented certificate: ${top_subject#subject=}"
echo "Its issuer (must be a bundle root): ${top_issuer#issuer=}"

# Split the bundle and find the issuer by exact subject match, then check the
# top cert's signature against that single root — mirroring esp_crt_bundle's
# issuer-name lookup + signature check.
mkdir "$workdir/roots"
awk -v dir="$workdir/roots" '/BEGIN CERTIFICATE/{n++; f=dir "/root-" n ".pem"} f{print > f} /END CERTIFICATE/{f=""}' "$bundle"

for root in "$workdir"/roots/root-*.pem; do
  if [ "$(openssl x509 -in "$root" -noout -subject)" = "${top_issuer/issuer=/subject=}" ]; then
    if openssl verify -partial_chain -trusted "$root" "$top" >/dev/null 2>&1; then
      echo "OK: device will trust this chain (issuer found in bundle, signature valid)."
      exit 0
    fi
  fi
done

echo "FAIL: the top presented certificate's issuer is not in the bundle (or its" >&2
echo "signature does not verify). Devices WILL fail TLS against ${host} even if" >&2
echo "desktop 'openssl verify' reports OK. Add the missing root to" >&2
echo "data/cert/extra-roots.pem and regenerate." >&2
exit 1
