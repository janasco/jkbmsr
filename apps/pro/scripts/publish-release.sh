#!/usr/bin/env bash
set -euo pipefail

# Builds a signed release APK + AAB locally and publishes the APK to the
# public download path (api.jkbmsr.com/mobile/latest.apk) plus a tagged
# GitHub Release for history. Replaces the old GitHub Actions workflow.
#
# Prerequisites:
#   - Flutter SDK on PATH (3.35.x verified)
#   - android/key.properties + android/upload-keystore.jks present (gitignored)
#   - scripts/.env.local present (gitignored) with MOBILE_RELEASE_UPLOAD_SECRET
#   - `gh` authenticated against jkbmsr/jkbmsr-pro
#
# Usage: scripts/publish-release.sh [version]
#   version defaults to the value in pubspec.yaml (e.g. "1.3.31"). Any "+build"
#   suffix in pubspec.yaml is the Android versionCode and is stripped, because
#   Pro's GitHub tag and artifact names carry the marketing version only
#   (v1.3.31, not v1.3.31+63). The GitHub tag is prefixed with "v".

cd "$(dirname "$0")/.."

if [[ ! -f scripts/.env.local ]]; then
  echo "Missing scripts/.env.local with MOBILE_RELEASE_UPLOAD_SECRET" >&2
  exit 1
fi
if [[ ! -f android/key.properties || ! -f android/upload-keystore.jks ]]; then
  echo "Missing android/key.properties + android/upload-keystore.jks (release signing)" >&2
  exit 1
fi
# scripts/.env.local may hold either "MOBILE_RELEASE_UPLOAD_SECRET=<value>" or
# just the bare secret value; accept both.
set -a
if grep -q "=" scripts/.env.local; then
  source scripts/.env.local
else
  MOBILE_RELEASE_UPLOAD_SECRET="$(tr -d '\n\r' < scripts/.env.local)"
fi
set +a
if [[ -z "${MOBILE_RELEASE_UPLOAD_SECRET:-}" ]]; then
  echo "MOBILE_RELEASE_UPLOAD_SECRET is empty in scripts/.env.local" >&2
  exit 1
fi

VERSION="${1:-$(grep -m1 '^version:' pubspec.yaml | awk '{print $2}')}"
# Strip the "+63" Android versionCode: Pro's tag and artifact names use the
# marketing version only. Without this a bare `publish-release.sh` creates
# v1.3.31+63 while the changelog and every previous Pro release say v1.3.31.
VERSION="${VERSION%%+*}"
VERSION_NUMBER="${VERSION}"
TAG="v${VERSION}"

echo "==> Building signed release APK + AAB ($VERSION)"
flutter pub get
flutter build apk --release
flutter build appbundle --release

APK="build/app/outputs/flutter-apk/app-release.apk"
AAB="build/app/outputs/bundle/release/app-release.aab"
APK_NAME="jkbmsr-pro-v${VERSION}.apk"
AAB_NAME="jkbmsr-pro-v${VERSION}.aab"
APK_SHA="$(sha256sum "$APK" | awk '{print $1}')"
AAB_SHA="$(sha256sum "$AAB" | awk '{print $1}')"
cp "$APK" "$APK_NAME"
cp "$AAB" "$AAB_NAME"
echo "$APK_SHA  $APK_NAME" > "${APK_NAME}.sha256"
echo "$AAB_SHA  $AAB_NAME" > "${AAB_NAME}.sha256"
echo "APK: $APK_NAME ($(stat -c%s "$APK") bytes)"
echo "AAB: $AAB_NAME ($(stat -c%s "$AAB") bytes)"

echo "==> Verifying 16 KB page-size alignment (required by Google Play)"
python3 "$(cd ../.. && pwd)/scripts/check-16kb-alignment.py" "$AAB"

echo "==> Extracting Play Store release notes (skipped if no changelog entry)"
WHATS_NEW=""
if [[ -f scripts/extract_changelog.py ]]; then
  if python3 scripts/extract_changelog.py "v${VERSION}" whatsnew-en-US.txt 2>/dev/null; then
    WHATS_NEW="whatsnew-en-US.txt"
  else
    echo "No changelog entry for v${VERSION}; continuing without notes."
  fi
fi

echo "==> Creating GitHub Release v${VERSION} (history only)"
ASSETS=("$APK_NAME" "${APK_NAME}.sha256" "$AAB_NAME" "${AAB_NAME}.sha256")
[[ -n "$WHATS_NEW" ]] && ASSETS+=("$WHATS_NEW")
{
  echo "Release: v${VERSION}"
  echo "Built: $(date -u)"
  echo ""
  echo "APK SHA256: ${APK_SHA}"
  echo "AAB SHA256: ${AAB_SHA}"
  echo ""
  echo "The .apk is for direct/sideload installs. The .aab goes to Google Play Console."
} > notes.txt
if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" --clobber "${ASSETS[@]}"
else
  gh release create "$TAG" --title "JK BMS Remote v${VERSION}" --notes-file notes.txt \
    "${ASSETS[@]}"
fi

echo "==> Publishing v${VERSION} to api.jkbmsr.com/mobile/latest.apk"
# Raw body upload (not multipart): version/sha256 travel in the query string and
# the APK is streamed straight through the Worker into R2, so Worker memory
# stays flat for 55MB+ APKs (multipart parsing buffered the whole file).
# Uses the shared Python uploader instead of curl, which is broken on some
# build hosts (the secret is read from the environment, never passed as an
# argument, so it cannot leak into the process list).
REPO_ROOT="$(cd ../.. && pwd)"
python3 "${REPO_ROOT}/scripts/upload-release.py" \
  --url "https://api.jkbmsr.com/mobile/release" \
  --version "${VERSION_NUMBER}" \
  --sha256 "${APK_SHA}" \
  --file "${APK_NAME}" \
  --secret-env MOBILE_RELEASE_UPLOAD_SECRET

echo
echo "==> Done. Download: https://api.jkbmsr.com/mobile/latest.apk"