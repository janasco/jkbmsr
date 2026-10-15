#!/usr/bin/env bash
set -euo pipefail

# Builds the signed release artifacts for JK BMS Contributor:
#   - app-release.apk  (direct/sideload + device testing), and
#   - app-release.aab  (the Google Play upload bundle).
# Verifies 16 KB page-size alignment (a Google Play requirement), writes a
# SHA-256 for each, and creates/updates a tagged GitHub Release for history.
#
# Deliberately NO CDN upload step. apps/ble and apps/pro each publish their
# latest APK to api.jkbmsr.com/{ble,mobile}/latest.apk through the Worker's
# POST /ble/release and POST /mobile/release (backend/src/routes/releases.ts).
# There is no Contributor download endpoint and no CONTRIBUTOR_RELEASE_UPLOAD_
# SECRET — Contributor is distributed through Google Play only, so its release
# artifact is the .aab. Adding a CDN path would mean a new backend route,
# bucket prefix and secret, which is a deliberate decision, not a script change.
#
# Prerequisites:
#   - Flutter SDK on PATH
#   - android/key.properties + the Contributor upload keystore (gitignored;
#     see android/key.properties.example) — without them the build falls back
#     to debug signing and the bundle cannot be uploaded to Play
#   - `gh` authenticated, with a remote pointing at janasco/jkbmsr (the
#     consolidated monorepo; releases are cut there as history)
#
# Usage: scripts/publish-release.sh [version]
#   version defaults to pubspec.yaml (e.g. "1.0.0+1"). The Android versionCode
#   is the "+1" suffix and is stripped from the tag and artifact names, so the
#   tag is contributor-v1.0.0, matching the family's marketing-version tags.

cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter not found on PATH" >&2
  exit 1
fi
if [[ ! -f android/key.properties ]]; then
  echo "Missing android/key.properties (release signing)." >&2
  echo "See android/key.properties.example. Refusing to build a store artifact with debug signing." >&2
  exit 1
fi
# The keystore is wherever key.properties says it is, not necessarily a file in
# this tree. Contributor deliberately keeps its upload key in the PRIVATE repo
# (jkbmsr-private/secrets/android-upload/), because this app lives in the public
# repository and a keystore under it would be one stray `git add` from being
# published. So resolve storeFile instead of looking for a local copy.
STORE_FILE="$(grep -m1 '^storeFile=' android/key.properties | cut -d= -f2- || true)"
if [[ -z "$STORE_FILE" || ! -f "$STORE_FILE" ]]; then
  echo "storeFile in android/key.properties is unset or does not exist: ${STORE_FILE:-<unset>}" >&2
  echo "Refusing to build a store artifact with debug signing." >&2
  exit 1
fi

VERSION="${1:-$(grep -m1 '^version:' pubspec.yaml | awk '{print $2}')}"
VERSION_NUMBER="${VERSION%%+*}"
TAG="contributor-v${VERSION_NUMBER}"

echo "==> Building signed release APK + AAB (${VERSION})"
flutter pub get
flutter build apk --release
flutter build appbundle --release

APK="build/app/outputs/flutter-apk/app-release.apk"
AAB="build/app/outputs/bundle/release/app-release.aab"
APK_NAME="jkbmsr-contributor-v${VERSION}.apk"
AAB_NAME="jkbmsr-contributor-v${VERSION}.aab"
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

echo "==> Creating GitHub Release ${TAG} (history only)"
{
  echo "Release: ${TAG}"
  echo "Built: $(date -u)"
  echo ""
  echo "APK SHA256: ${APK_SHA}"
  echo "AAB SHA256: ${AAB_SHA}"
  echo ""
  echo "Contributor is distributed through Google Play. Upload ${AAB_NAME} to"
  echo "Play Console (internal testing, then production); the .apk is for"
  echo "direct/sideload installs and device testing only."
} > notes.txt
ASSETS=("$APK_NAME" "${APK_NAME}.sha256" "$AAB_NAME" "${AAB_NAME}.sha256")
if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" --clobber "${ASSETS[@]}"
else
  gh release create "$TAG" --title "JK BMS Contributor v${VERSION_NUMBER}" \
    --notes-file notes.txt "${ASSETS[@]}"
fi

echo
# The listing, the data-safety form, the screenshots and the app's FIRST publish
# were all completed by hand on 2026-10-15. Since then the bundle is uploaded and
# promoted through the Play Publisher API, so there is no console step here — and
# an earlier version of this block told the reader to upload to Internal testing
# and fill forms that were already done.
echo "==> Publishing (no console step needed):"
echo "    Upload ${AAB_NAME} and promote via the Play Publisher API. See"
echo "    jkbmsr-private/brand/store-listing/PLAY-LISTING-CONTRIBUTOR.md for the"
echo "    procedure and the current track state."
echo "==> No CDN upload: Contributor has no api.jkbmsr.com download endpoint."
