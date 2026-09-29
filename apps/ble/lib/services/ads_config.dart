import 'package:flutter/foundation.dart';

import 'entitlement_service.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// ADS ARE OFF until an AdMob application id exists. They must stay off until
/// then.
///
/// This file is the single ad decision. The SDK is now wired (see
/// `lib/widgets/ad_slot.dart` and `lib/services/ad_sdk.dart`), but it is inert
/// under the shipped default: with no `--dart-define` [current] is
/// `isConfigured: false`, so [mayShowAds] is false for every user, [AdSlot]
/// renders nothing, and the Google Mobile Ads SDK is never initialised and
/// never contacted. `test/ad_slot_test.dart` and `test/ad_sdk_test.dart` assert
/// exactly that.
///
/// Turning ads on is ONE deliberate build invocation, with no code edit:
///
///   flutter build apk \
///     --dart-define=ADMOB_APP_ID=ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY \
///     --dart-define=ADS_ENABLED=true
///     # optional, for real creatives; without it Google's TEST ad is served:
///     # --dart-define=ADMOB_BANNER_AD_UNIT_ID=ca-app-pub-XXXXXXXXXXXXXXXX/ZZZZZZZZZZ
///
/// [admobAppIdFromEnvironment] and [adsEnabledInBuild] are read at compile
/// time, so [current] stays `isConfigured: false` / `enabledInThisBuild:
/// false` / `admobAppId: null` in any build that does not pass them: the SDK is
/// not initialised, no ad request is made, and the app behaves exactly as it
/// does today.
///
/// The entitlement that suppresses ads already ships and is already honoured
/// here ([mayShowAds]): a Supporter is rejected before [AdSlot] builds an ad,
/// and [AdSdk.ensureInitialised] re-checks the same gate before it touches the
/// SDK — so a Supporter never initialises it.
///
/// Where ads may NOT go, even once they are enabled: the Connect/Scanning
/// flow, the Control screen, the PIN dialog, and anything rendered while a
/// BLE connection is being established. Ads belong on read-only status and
/// history surfaces only.
/// ─────────────────────────────────────────────────────────────────────────

/// The single place in this app that decides whether an ad may be shown.
///
/// Every ad placement goes through one [AdSlot] widget, and [AdSlot] asks
/// [mayShowAds] — so there is exactly one ad decision in the codebase, and it
/// is the combination of "ads are actually configured for this build" and
/// "this user is not a Supporter".
@immutable
class AdsConfig {
  const AdsConfig({
    required this.isConfigured,
    required this.enabledInThisBuild,
    this.admobAppId,
    this.bannerAdUnitId = _bannerAdUnitIdFromEnvironment,
  });

  /// The AdMob application id for `com.jkbmsr.ble`, supplied at build time
  /// with `--dart-define=ADMOB_APP_ID=ca-app-pub-…`. Empty when the define is
  /// absent, which is the shipped default and means "not configured".
  ///
  /// NOTE: the native SDK reads the application id from the
  /// `com.google.android.gms.ads.APPLICATION_ID` meta-data in
  /// `android/app/src/main/AndroidManifest.xml`, NOT from this define. A real
  /// build therefore needs BOTH: the manifest value replaced and this define
  /// passed (the define is what flips [isConfigured], and therefore the gate).
  static const String admobAppIdFromEnvironment =
      String.fromEnvironment('ADMOB_APP_ID');

  /// The deliberate ads kill switch, supplied at build time with
  /// `--dart-define=ADS_ENABLED=true`. It defaults to off, so even a build
  /// carrying a real id does not show ads until this is turned on (a Play
  /// review build, or a rollout held back while the Supporter entitlement is
  /// being verified).
  static const bool adsEnabledInBuild =
      bool.fromEnvironment('ADS_ENABLED');

  /// Google's public **test** banner ad unit for Android.
  ///
  /// It can never serve a live ad, which is why it is the default: a build
  /// that has been switched on before a real unit id exists shows Google's
  /// test creative and never a real, unreviewed ad. Swap in the real id with
  /// `--dart-define=ADMOB_BANNER_AD_UNIT_ID=ca-app-pub-…/…`.
  static const String googleTestBannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';

  /// Banner ad unit, supplied at build time with
  /// `--dart-define=ADMOB_BANNER_AD_UNIT_ID=ca-app-pub-…/…`. It falls back to
  /// [googleTestBannerAdUnitId], so a configured dev/test build is safe by
  /// default and real ads are a separate, deliberate define.
  ///
  /// See `apps/ble/README.md` ("Enabling real AdMob ads") for the full
  /// invocation.
  static const String _bannerAdUnitIdFromEnvironment =
      String.fromEnvironment('ADMOB_BANNER_AD_UNIT_ID',
          defaultValue: googleTestBannerAdUnitId);

  /// What ships today. With no `--dart-define` this is `isConfigured: false`,
  /// `enabledInThisBuild: false`, `admobAppId: null`, so [mayShowAds] is false
  /// for every user on every build and no ad is ever requested.
  static const AdsConfig current = AdsConfig(
    isConfigured: admobAppIdFromEnvironment != '',
    enabledInThisBuild: adsEnabledInBuild,
    admobAppId:
        admobAppIdFromEnvironment == '' ? null : admobAppIdFromEnvironment,
  );

  /// True once a real AdMob application id exists and the SDK is present.
  /// Until then this is `false` and that alone keeps every ad off.
  final bool isConfigured;

  /// A deliberate on/off switch, separate from configuration, so a build can
  /// ship with ids in place while ads stay off (e.g. a Play review build, or
  /// while the Supporter entitlement is being verified).
  final bool enabledInThisBuild;

  /// The AdMob application id for `com.jkbmsr.ble`. `null` unless a real id
  /// was supplied at build time: it must not be invented, and an AdMob SDK
  /// initialises with a *malformed* placeholder id rather than failing loudly.
  final String? admobAppId;

  /// The banner ad unit the real ad request uses. Never null: when no real
  /// unit id was supplied this is [googleTestBannerAdUnitId], which cannot
  /// serve a live ad. It is only ever read after [mayShowAds] has returned
  /// true, so it cannot cause a request on its own.
  final String bannerAdUnitId;

  /// True when this build will request Google's test creatives rather than
  /// live ads. Useful for a startup log line; never a permission to show ads.
  bool get usesTestAdUnits => bannerAdUnitId == googleTestBannerAdUnitId;

  /// THE ad decision.
  ///
  /// Fails safe in both directions: no configuration (today) and a Supporter
  /// entitlement both mean "no ad". An unentitled user is only shown an ad
  /// once ads have been deliberately configured *and* switched on.
  bool mayShowAds(EntitlementState entitlement) =>
      isConfigured && enabledInThisBuild && !entitlement.adFree;
}
