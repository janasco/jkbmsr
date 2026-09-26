import 'package:flutter/foundation.dart';

import 'entitlement_service.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// ADS ARE OFF. They must stay off until an AdMob application id exists.
///
/// There is no AdMob account for `com.jkbmsr.ble` and therefore no app id, no
/// ad-unit id and no ad SDK in `pubspec.yaml`. A real SDK cannot be added
/// without an app id (it fails to initialise and the app is rejected if the id
/// is a placeholder), so nothing here is wired to Google Mobile Ads — by
/// design, not by omission.
///
/// What ships instead is the seam, so that turning ads on later is ONE
/// deliberate change rather than a hunt through the UI:
///   1. add the SDK dependency and put the real ids in [AdsConfig.current];
///   2. flip [AdsConfig.isConfigured] / [enabledInThisBuild];
///   3. replace the placeholder in `AdSlot` with the SDK's widget.
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

  /// What ships today. `isConfigured: false` means there is no AdMob app id,
  /// so [mayShowAds] is false for every user on every build and no ad is ever
  /// requested from the network.
  static const AdsConfig current = AdsConfig(
    isConfigured: false,
    enabledInThisBuild: false,
    admobAppId: null,
  );

  /// True once a real AdMob application id exists and the SDK is present.
  /// Until then this is `false` and that alone keeps every ad off.
  final bool isConfigured;

  /// A deliberate on/off switch, separate from configuration, so a build can
  /// ship with ids in place while ads stay off (e.g. a Play review build, or
  /// while the Supporter entitlement is being verified).
  final bool enabledInThisBuild;

  /// The AdMob application id for `com.jkbmsr.ble`. Deliberately `null`: it
  /// must not be invented, and an AdMob SDK initialises with a *malformed*
  /// placeholder id rather than failing loudly.
  final String? admobAppId;

  /// THE ad decision.
  ///
  /// Fails safe in both directions: no configuration (today) and a Supporter
  /// entitlement both mean "no ad". An unentitled user is only shown an ad
  /// once ads have been deliberately configured *and* switched on.
  bool mayShowAds(EntitlementState entitlement) =>
      isConfigured && enabledInThisBuild && !entitlement.adFree;
}
