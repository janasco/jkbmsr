#!/usr/bin/env bash
#
# The AdMob identifiers passed to release builds of `com.jkbmsr.ble`.
#
# These are PUBLIC values (an AdMob application id and ad unit id are not
# secrets — they ship inside every APK/AAB and are visible in the AdMob
# console), so they belong in the repository rather than in `secrets/`.
#
# A build with NO --dart-define stays inert: `AdsConfig.current` is
# `isConfigured: false`, so no ad is ever requested and the Google Mobile Ads
# SDK is never initialised (see lib/services/ads_config.dart and the
# ad_slot/ad_sdk tests). Only the two release scripts source this file, so
# `flutter test` and a default `flutter build` remain ad-free.
#
# Sourced by scripts/build-play-aab.sh and scripts/publish-release.sh so the
# two release paths cannot drift apart; this is the single place the ids live.

ADMOB_APP_ID_RELEASE="ca-app-pub-7509069315268105~6175254978"
ADMOB_BANNER_AD_UNIT_ID_RELEASE="ca-app-pub-7509069315268105/7677882212"

# Passed verbatim to `flutter build … "${ADMOB_DART_DEFINES[@]}"`.
# The manifest also carries the real APPLICATION_ID (the native SDK reads it
# from there, not from the define); both must name the same app or the gate
# and the SDK disagree.
ADMOB_DART_DEFINES=(
  "--dart-define=ADMOB_APP_ID=${ADMOB_APP_ID_RELEASE}"
  "--dart-define=ADMOB_BANNER_AD_UNIT_ID=${ADMOB_BANNER_AD_UNIT_ID_RELEASE}"
  "--dart-define=ADS_ENABLED=true"
)
