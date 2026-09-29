// The ad seam: exactly one place decides whether an ad may show, and exactly
// one widget renders one.
//
// Under the shipped config (`AdsConfig.current`, no --dart-define) the first
// block must render NOTHING and the SDK must never be touched, for both an
// unentitled and an entitled user. The configured cases use an injected fake
// builder, so they prove the gate order without ever loading the real SDK in a
// test; a Supporter must short-circuit before that fake is reached at all.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jkbmsr_ble/services/ads_config.dart';
import 'package:jkbmsr_ble/services/entitlement_service.dart';
import 'package:jkbmsr_ble/widgets/ad_slot.dart';

/// A configuration as it will look once an AdMob app id exists.
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
  tearDown(() => EntitlementService.instance.debugResetState());

  /// Counts how many times the ad widget was actually built, and renders a
  /// recognisable stand-in instead of a real SDK banner.
  int builtCount = 0;
  Widget fakeAd(BuildContext context, AdsConfig config, EntitlementState e) {
    builtCount++;
    return Text('fake-ad:${config.bannerAdUnitId}');
  }

  setUp(() => builtCount = 0);

  Future<void> pumpSlot(
    WidgetTester tester, {
    AdsConfig config = AdsConfig.current,
    AdSlotAdBuilder? builder,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        // Center, not a tight SizedBox: a slot must size itself to its child,
        // and a disabled one must be 0x0 rather than filling the screen.
        body: Center(child: AdSlot(config: config, adBuilder: builder)),
      ),
    ));
    await tester.pump();
  }

  group('AdsConfig (the one ad decision)', () {
    test('is not configured in any shipped build', () {
      expect(AdsConfig.current.isConfigured, isFalse,
          reason: 'there is no AdMob app id for com.jkbmsr.ble — ads stay off');
      expect(AdsConfig.current.admobAppId, isNull,
          reason: 'an ad unit/app id must never be invented');
    });

    test('mayShowAds is false for an unentitled user while unconfigured', () {
      expect(AdsConfig.current.mayShowAds(_playUser), isFalse);
    });

    test('mayShowAds is false for a Supporter even when configured', () {
      expect(_configuredAds.mayShowAds(_supporter), isFalse);
    });

    test('mayShowAds is true only for an unentitled, configured, enabled build',
        () {
      expect(_configuredAds.mayShowAds(_playUser), isTrue);
    });

    test('mayShowAds is false when configured but deliberately switched off',
        () {
      const switchedOff = AdsConfig(
        isConfigured: true,
        enabledInThisBuild: false,
        admobAppId: 'ca-app-pub-0000000000000000',
      );
      expect(switchedOff.mayShowAds(_playUser), isFalse);
    });

    test('defaults to Google test ad units, never a real id', () {
      expect(AdsConfig.current.bannerAdUnitId,
          AdsConfig.googleTestBannerAdUnitId);
      expect(_configuredAds.bannerAdUnitId,
          AdsConfig.googleTestBannerAdUnitId);
      expect(_configuredAds.usesTestAdUnits, isTrue);
    });
  });

  group('AdSlot', () {
    testWidgets('renders nothing in the shipped configuration', (tester) async {
      EntitlementService.instance.debugOverrideState(_playUser);
      await pumpSlot(tester, builder: fakeAd);

      expect(find.byType(AdSlot), findsOneWidget);
      expect(find.textContaining('fake-ad'), findsNothing);
      expect(builtCount, 0,
          reason: 'the real ad path must not be reached without dart-defines');
      expect(tester.getSize(find.byType(AdSlot)), Size.zero,
          reason: 'a disabled ad must not reserve any layout space');
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders nothing for a Supporter even when configured',
        (tester) async {
      EntitlementService.instance.debugOverrideState(_supporter);
      await pumpSlot(tester, config: _configuredAds, builder: fakeAd);

      expect(find.textContaining('fake-ad'), findsNothing);
      expect(builtCount, 0,
          reason: 'a Supporter must short-circuit before an ad is built');
      expect(tester.getSize(find.byType(AdSlot)), Size.zero);
    });

    testWidgets('renders an ad for an unentitled user once configured',
        (tester) async {
      EntitlementService.instance.debugOverrideState(_playUser);
      await pumpSlot(tester, config: _configuredAds, builder: fakeAd);

      expect(find.textContaining('fake-ad'), findsOneWidget);
      expect(builtCount, 1);
    });

    testWidgets('follows the entitlement when it resolves after mount',
        (tester) async {
      EntitlementService.instance.debugOverrideState(
        const EntitlementState(installKind: InstallKind.play),
      );
      await pumpSlot(tester, config: _configuredAds, builder: fakeAd);
      expect(find.textContaining('fake-ad'), findsOneWidget);

      // The entitlement lands after the first frame (a restore, or a purchase
      // completing) and the slot has to disappear without a rebuild of the
      // screen that hosts it.
      EntitlementService.instance.debugOverrideState(_supporter);
      await tester.pump();

      expect(find.textContaining('fake-ad'), findsNothing);
    });
  });
}
