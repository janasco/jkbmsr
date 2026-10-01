#!/usr/bin/env bash
set -euo pipefail

# Builds a signed release APK locally and publishes it to the public download
# path (api.jkbmsr.com/ble/latest.apk) plus a tagged GitHub Release for
# history. Replaces the old GitHub Actions release workflow.
#
# Prerequisites:
#   - Flutter SDK on PATH (pinned in docs; version 3.35.x verified)
#   - android/key.properties + android/upload-keystore.jks present (gitignored)
#   - scripts/.env.local present (gitignored) with BLE_RELEASE_UPLOAD_SECRET
#   - `gh` authenticated against jkbmsr/jkbmsr-ble
#
# Usage: scripts/publish-release.sh [version]
#   version defaults to the value in pubspec.yaml (e.g. "4.15.0"). The
#   GitHub tag is prefixed with "v"), e.g. v4.15.0.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."
# shellcheck source=scripts/ads-defines.sh
source "$SCRIPT_DIR/ads-defines.sh"

if [[ ! -f scripts/.env.local ]]; then
  echo "Missing scripts/.env.local with BLE_RELEASE_UPLOAD_SECRET" >&2
  exit 1
fi
if [[ ! -f android/key.properties || ! -f android/upload-keystore.jks ]]; then
  echo "Missing android/key.properties + android/upload-keystore.jks (release signing)" >&2
  exit 1
fi
set -a; source scripts/.env.local; set +a
if [[ -z "${BLE_RELEASE_UPLOAD_SECRET:-}" ]]; then
  echo "BLE_RELEASE_UPLOAD_SECRET is empty in scripts/.env.local" >&2
  exit 1
fi

VERSION="${1:-$(grep -m1 '^version:' pubspec.yaml | awk '{print $2}')}"
VERSION_NUMBER="${VERSION%+*}"
TAG="v${VERSION}"

echo "==> Building signed release APK ($VERSION) with ads enabled"
flutter pub get
flutter build apk --release "${ADMOB_DART_DEFINES[@]}"

APK="build/app/outputs/flutter-apk/app-release.apk"
APK_NAME="jkbmsr-ble-v${VERSION}.apk"
SHA256="$(sha256sum "$APK" | awk '{print $1}')"
cp "$APK" "$APK_NAME"
echo "$SHA256  $APK_NAME" > "${APK_NAME}.sha256"
echo "APK: $APK_NAME ($(stat -c%s "$APK") bytes)"
echo "SHA256: $SHA256"

echo "==> Creating GitHub Release v${VERSION} (history only)"
{
  echo "Release: v${VERSION}"
  echo "Built: $(date -u)"
  echo "APK SHA256: ${SHA256}"
} > notes.txt
if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" --clobber "$APK_NAME" "${APK_NAME}.sha256"
else
  gh release create "$TAG" --title "JKBMSR BLE v${VERSION}" --notes-file notes.txt \
    "$APK_NAME" "${APK_NAME}.sha256"
fi

echo "==> Publishing v${VERSION} to api.jkbmsr.com/ble/latest.apk"
# Raw body upload (not multipart): version/sha256 travel in the query string and
# the APK is streamed straight through the Worker into R2, so Worker memory
# stays flat for 55MB+ APKs (multipart parsing buffered the whole file).
# Uses the shared Python uploader instead of curl, which is broken on some
# build hosts (the secret is read from the environment, never passed as an
# argument, so it cannot leak into the process list).
REPO_ROOT="$(cd ../.. && pwd)"
python3 "${REPO_ROOT}/scripts/upload-release.py" \
  --url "https://api.jkbmsr.com/ble/release" \
  --version "${VERSION_NUMBER}" \
  --sha256 "${SHA256}" \
  --file "${APK_NAME}" \
  --secret-env BLE_RELEASE_UPLOAD_SECRET

echo
echo "==> Done. Download: https://api.jkbmsr.com/ble/latest.apk"