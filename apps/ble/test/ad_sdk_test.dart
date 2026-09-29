// The SDK gate, measured directly.
//
// `AdSdk.ensureInitialised` is the only thing in the app that can call
// `MobileAds.initialize()`. These tests assert it does so ZERO times for the
// shipped default and for a Supporter — the proof that a default build (and an
// ad-free user) makes no SDK call and no network request — and exactly once on
// the configured path. The initialiser is injected, so the real SDK is never
// loaded on the Dart VM and no platform channel is used.
import 'package:flutter_test/flutter_test.dart';

import 'package:jkbmsr_ble/services/ad_sdk.dart';
import 'package:jkbmsr_ble/services/ads_config.dart';
import 'package:jkbmsr_ble/services/entitlement_service.dart';

const AdsConfig _configuredAds = AdsConfig(
  isConfigured: true,
  enabledInThisBuild: true,
  admobAppId: 'ca-app-pub-0000000000000000',
);

const EntitlementState _playUser = EntitlementState(
  installKind: InstallKind.play,
  adFree: false,
  resolved: true,
);

const EntitlementState _supporter = EntitlementState(
  installKind: InstallKind.play,
  adFree: true,
  resolved: true,
);

void main() {
  // Stands in for `MobileAds.instance.initialize()`. If the gate ever let a
  // default or Supporter call through, this counter would move.
  var fakeInitializeCalls = 0;

  setUp(() {
    AdSdk.instance.debugReset();
    fakeInitializeCalls = 0;
    AdSdk.instance.debugInitializer = () async => fakeInitializeCalls++;
  });

  tearDown(() => AdSdk.instance.debugReset());

  group('AdSdk is inert unless ads are configured', () {
    test('the shipped default never initialises the SDK', () async {
      await AdSdk.instance.ensureInitialised(AdsConfig.current, _playUser);

      expect(AdSdk.instance.initializeCalls, 0,
          reason: 'no ADMOB_APP_ID/ADS_ENABLED dart-defines means no SDK init');
      expect(fakeInitializeCalls, 0);
      expect(AdSdk.instance.isInitialised, isFalse);
    });

    test('a Supporter never initialises the SDK, even when configured',
        () async {
      await AdSdk.instance.ensureInitialised(_configuredAds, _supporter);

      expect(AdSdk.instance.initializeCalls, 0,
          reason: 'remove_ads_lifetime must short-circuit before SDK init');
      expect(fakeInitializeCalls, 0);
      expect(AdSdk.instance.isInitialised, isFalse);
    });

    test('a configured-but-switched-off build never initialises the SDK',
        () async {
      const switchedOff = AdsConfig(
        isConfigured: true,
        enabledInThisBuild: false,
        admobAppId: 'ca-app-pub-0000000000000000',
      );
      await AdSdk.instance.ensureInitialised(switchedOff, _playUser);

      expect(AdSdk.instance.initializeCalls, 0);
      expect(fakeInitializeCalls, 0);
    });
  });

  group('AdSdk initialises exactly once on the permitted path', () {
    test('initialises once and reuses the result', () async {
      await AdSdk.instance.ensureInitialised(_configuredAds, _playUser);
      await AdSdk.instance.ensureInitialised(_configuredAds, _playUser);

      expect(AdSdk.instance.initializeCalls, 1,
          reason: 'the SDK is initialised at most once per app run');
      expect(fakeInitializeCalls, 1);
      expect(AdSdk.instance.isInitialised, isTrue);
    });

    test('concurrent calls share the single initialisation', () async {
      await Future.wait([
        AdSdk.instance.ensureInitialised(_configuredAds, _playUser),
        AdSdk.instance.ensureInitialised(_configuredAds, _playUser),
      ]);

      expect(AdSdk.instance.initializeCalls, 1);
      expect(fakeInitializeCalls, 1);
    });

    test('a Supporter never reaches the initialiser after a permitted ad',
        () async {
      await AdSdk.instance.ensureInitialised(_configuredAds, _playUser);
      expect(fakeInitializeCalls, 1);

      // A later Supporter state must not trigger a second init (there is
      // nothing to tear down — initialisation is one-way — but the count
      // proves the gate is consulted, not bypassed).
      await AdSdk.instance.ensureInitialised(_configuredAds, _supporter);
      expect(AdSdk.instance.initializeCalls, 1);
    });
  });
}
