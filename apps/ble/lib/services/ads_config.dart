import 'package:flutter/foundation.dart';

import 'entitlement_service.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// ADS ARE OFF until an AdMob application id exists. They must stay off until
/// then.
///
/// There is no AdMob account for `com.jkbmsr.ble` and therefore no app id and
/// no ad-unit id. A real SDK cannot be used without an app id (it fails to
/// initialise and the app is rejected if the id is a placeholder), so nothing
/// here is wired to Google Mobile Ads — by design, not by omission.
///
/// What ships instead is the seam, so that turning ads on later is ONE
/// deliberate build invocation with no code edit:
///
///   flutter build apk \
///     --dart-define=ADMOB_APP_ID=ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY \
///     --dart-define=ADS_ENABLED=true
///
/// [admobAppIdFromEnvironment] and [adsEnabledInBuild] are read at compile
/// time, so [current] stays `isConfigured: false` / `enabledInThisBuild:
/// false` / `admobAppId: null` in any build that does not pass them: no ad
/// request is ever made and the app behaves exactly as it does today.
///
/// The entitlement that suppresses ads already ships and is already honoured
/// here ([mayShowAds]) — it just has nothing to suppress yet.
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
  });

  /// The AdMob application id for `com.jkbmsr.ble`, supplied at build time
  /// with `--dart-define=ADMOB_APP_ID=ca-app-pub-…`. Empty when the define is
  /// absent, which is the shipped default and means "not configured".
  static const String admobAppIdFromEnvironment =
      String.fromEnvironment('ADMOB_APP_ID');

  /// The deliberate ads kill switch, supplied at build time with
  /// `--dart-define=ADS_ENABLED=true`. It defaults to off, so even a build
  /// carrying a real id does not show ads until this is turned on (a Play
  /// review build, or a rollout held back while the Supporter entitlement is
  /// being verified).
  static const bool adsEnabledInBuild =
      bool.fromEnvironment('ADS_ENABLED');

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

  /// THE ad decision.
  ///
  /// Fails safe in both directions: no configuration (today) and a Supporter
  /// entitlement both mean "no ad". An unentitled user is only shown an ad
  /// once ads have been deliberately configured *and* switched on.
  bool mayShowAds(EntitlementState entitlement) =>
      isConfigured && enabledInThisBuild && !entitlement.adFree;
}
