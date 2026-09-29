import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_config.dart';
import 'entitlement_service.dart';

/// Owns the ONE call to [MobileAds.initialize] in this app.
///
/// It exists so the SDK is initialised **lazily, at most once per app run, and
/// only when the one ad decision ([AdsConfig.mayShowAds]) has already said
/// yes**. Nothing here runs at import time: [AdSdk.instance] is a plain
/// singleton and the SDK is untouched until [ensureInitialised] is called by
/// the real banner widget on the first permitted ad.
///
/// Consequences that are deliberately guaranteed, and tested in
/// `test/ad_sdk_test.dart`:
///  * the shipped default (`AdsConfig.current`, no `--dart-define`) never
///    reaches [MobileAds.initialize], so there is no SDK init and no request;
///  * a Supporter (`remove_ads_lifetime`) never reaches it either — the gate is
///    re-checked here, immediately before the SDK call, rather than trusted
///    from the caller;
///  * a build configured but deliberately switched off never reaches it.
///
/// The positive path is exercised with an injected initialiser (see
/// [debugInitializer]) so no real SDK is ever loaded on the Dart VM.
class AdSdk {
  AdSdk._();

  static final AdSdk instance = AdSdk._();

  Future<void>? _initialisation;
  bool _initialised = false;

  /// True once [MobileAds.initialize] has completed for this process.
  bool get isInitialised => _initialised;

  /// How many times the initialiser was actually invoked. This is the
  /// instrument the tests read to prove the SDK stays untouched for the
  /// shipped config and for a Supporter.
  @visibleForTesting
  int initializeCalls = 0;

  /// Test-only replacement for the real SDK entry point. Unset in the app, so
  /// the shipping code path is always [MobileAds.instance.initialize].
  @visibleForTesting
  Future<void> Function()? debugInitializer;

  /// Initialises the SDK at most once per app run, and ONLY when
  /// [AdsConfig.mayShowAds] permits an ad for [entitlement].
  ///
  /// [AdSlot] calls this immediately before it builds a real ad, so
  /// initialisation happens on the first permitted ad rather than at startup.
  /// Calling it again returns the same in-flight/completed future, so the SDK
  /// is never initialised twice.
  Future<void> ensureInitialised(
    AdsConfig config,
    EntitlementState entitlement,
  ) {
    // THE GATE, re-checked at the last possible moment. A Supporter, an
    // unconfigured build and a switched-off build must not reach
    // MobileAds.initialize() or the network at all.
    if (!config.mayShowAds(entitlement)) {
      return Future<void>.value();
    }
    return _initialisation ??= _initialise();
  }

  Future<void> _initialise() async {
    initializeCalls++;
    final initializer = debugInitializer ?? MobileAds.instance.initialize;
    await initializer();
    _initialised = true;
  }

  /// Test-only: forget the cached initialisation so a test starts clean. The
  /// app never calls this — initialisation is a process-lifetime fact.
  @visibleForTesting
  void debugReset() {
    _initialisation = null;
    _initialised = false;
    initializeCalls = 0;
    debugInitializer = null;
  }
}
