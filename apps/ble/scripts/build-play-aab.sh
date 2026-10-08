#!/usr/bin/env bash
set -euo pipefail

# Builds the Google Play upload bundle (.aab) WITHOUT the sideload-only
# REQUEST_INSTALL_PACKAGES permission.
#
# Play policy forbids Play-distributed apps from self-updating outside Play,
# so the Play AAB must not declare the permission at all (a runtime gate
# alone still triggers the Play Console declaration form). The sideload APK
# built by scripts/publish-release.sh keeps it.
#
# The manifest is restored afterwards; the only lasting artifacts are the
# versioned AAB + .sha256 in the repo root (gitignored, attached to the
# GitHub release for the Play Console upload).
#
# Prerequisites: flutter on PATH, android/key.properties +
# android/upload-keystore.jks present (same as publish-release.sh).
#
# Usage: scripts/build-play-aab.sh [version]  (defaults to pubspec.yaml)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."
# shellcheck source=scripts/ads-defines.sh
source "$SCRIPT_DIR/ads-defines.sh"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter not found on PATH" >&2
  exit 1
fi
if [[ ! -f android/key.properties || ! -f android/upload-keystore.jks ]]; then
  echo "Missing android/key.properties + android/upload-keystore.jks (release signing)" >&2
  exit 1
fi

VERSION="${1:-$(grep -m1 '^version:' pubspec.yaml | awk '{print $2}')}"

MANIFEST="android/app/src/main/AndroidManifest.xml"
cp "$MANIFEST" "$MANIFEST.bak"
restore() { mv "$MANIFEST.bak" "$MANIFEST"; }
trap restore EXIT

python3 - "$MANIFEST" <<'EOF'
import sys
path = sys.argv[1]
lines = open(path).read().splitlines(keepends=True)
idx = next(
    (i for i, l in enumerate(lines) if 'REQUEST_INSTALL_PACKAGES' in l), None)
if idx is None:
    sys.exit('permission not found in manifest')
start = idx
j = idx - 1
while j >= 0:
    s = lines[j].strip()
    if s == '' or (s.startswith('<') and not s.startswith('<!--')
                   and not s.endswith('-->')):
        break
    start = j
    j -= 1
del lines[start:idx + 1]
open(path, 'w').writelines(lines)
EOF

if grep -q "REQUEST_INSTALL_PACKAGES" "$MANIFEST"; then
  echo "FAILED to strip REQUEST_INSTALL_PACKAGES from manifest" >&2
  exit 1
fi
echo "==> Manifest stripped; building Play AAB ($VERSION) with ads enabled"
flutter build appbundle --release "${ADMOB_DART_DEFINES[@]}"

AAB="build/app/outputs/bundle/release/app-release.aab"
AAB_NAME="jkbmsr-ble-v${VERSION}.aab"
SHA256="$(sha256sum "$AAB" | awk '{print $1}')"
cp "$AAB" "$AAB_NAME"
echo "$SHA256  $AAB_NAME" > "${AAB_NAME}.sha256"
echo "AAB: $AAB_NAME ($(stat -c%s "$AAB") bytes)"
echo "SHA256: $SHA256"

echo
echo "==> Verifying 16 KB page-size alignment (required by Google Play)"
python3 "$(cd ../.. && pwd)/scripts/check-16kb-alignment.py" "$AAB_NAME"
