// The Support sheet sells exactly one thing: the one-time Google Play
// non-consumable (`remove_ads_lifetime`) that removes ads, plus its restore
// action. Donations were removed, so this guard pins two things:
//   * a Play build shows the Supporter unlock and no purchase otherwise;
//   * a sideloaded copy (or an unresolved channel) shows no purchase at all;
//   * nothing in the sheet sells, links to, or names a donation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jkbmsr_ble/services/entitlement_service.dart';
import 'package:jkbmsr_ble/widgets/support_modal.dart';
import 'package:jkbmsr_ble/widgets/supporter_section.dart';

import 'support/fake_in_app_purchase.dart';
import 'support/entitlement_test_harness.dart';

/// Pins the install channel on the app-wide service and installs a Play
/// Billing double, so a Play build's Supporter section can resolve its price
/// without a store (and without leaving a pending billing timer behind).
void _pinInstallChannel(InstallKind kind) {
  installFakePlayBilling(
    installedByPlay: kind == InstallKind.play,
    products: [supporterProduct()],
  );
  EntitlementService.instance.debugOverrideState(EntitlementState(
    installKind: kind,
    adFree: kind == InstallKind.sideload,
    resolved: true,
  ));
}

Future<void> _pumpSupportSheet(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(body: SupportModal(onClose: () {})),
  ));
  // StaggerIn runs a finite entrance animation.
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pump();
}

/// Walks every rendered string and fails if any of them sells, links to, or
/// even names a donation (or the retired Polar checkout). Case-insensitive so
/// a differently-cased reintroduction cannot slip past.
void _expectNoDonationSurface(WidgetTester tester) {
  final texts = find
      .byType(Text)
      .evaluate()
      .map((e) => ((e.widget as Text).data ?? '').toLowerCase());
  for (final text in texts) {
    for (final needle in const ['donate', 'donation', 'polar', 'support us']) {
      expect(text, isNot(contains(needle)),
          reason: 'the Support sheet must not reference "$needle" '
              '(found: "$text")');
    }
  }
}

void main() {
  tearDown(() => EntitlementService.instance.debugResetState());

  group('Google Play build', () {
    testWidgets('offers the Play Supporter unlock, and no donation surface',
        (tester) async {
      _pinInstallChannel(InstallKind.play);
      await _pumpSupportSheet(tester);

      expect(find.byType(SupporterSection), findsOneWidget);
      expect(find.text('SUPPORTER'), findsOneWidget);
      expect(find.text('RESTORE PURCHASE'), findsOneWidget);
      _expectNoDonationSurface(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('sideloaded build', () {
    testWidgets('offers no Play purchase, because there is no Play account',
        (tester) async {
      _pinInstallChannel(InstallKind.sideload);
      await _pumpSupportSheet(tester);

      expect(find.byType(SupporterSection), findsNothing);
      expect(find.text('RESTORE PURCHASE'), findsNothing);
      expect(find.textContaining('already ad-free'), findsOneWidget);
      _expectNoDonationSurface(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('unresolved install channel', () {
    testWidgets('offers no purchase until the channel is proven',
        (tester) async {
      EntitlementService.instance.debugOverrideState(const EntitlementState());
      await _pumpSupportSheet(tester);

      expect(find.byType(SupporterSection), findsNothing);
      _expectNoDonationSurface(tester);
    });
  });

  group('copy', () {
    testWidgets('says the app is ad-free while no ad is configured',
        (tester) async {
      // The state a real shipped build is in: a Play copy, no Supporter
      // purchase, and no AdMob app id — so there is nothing to remove yet.
      _pinInstallChannel(InstallKind.play);
      await _pumpSupportSheet(tester);

      expect(find.textContaining('free and ad-free'), findsOneWidget);
    });

    testWidgets('tells a Supporter their copy is ad-free', (tester) async {
      _pinInstallChannel(InstallKind.play);
      EntitlementService.instance
          .debugOverrideState(const EntitlementState(
            installKind: InstallKind.play,
            adFree: true,
            resolved: true,
          ));
      await _pumpSupportSheet(tester);

      expect(find.textContaining('You are a Supporter'), findsOneWidget);
      expect(find.text('Ads are off for good.'), findsOneWidget);
      expect(find.text('REMOVE ADS'), findsNothing,
          reason: 'an owned unlock must not still be for sale');
    });

    testWidgets('never promises support for another battery brand',
        (tester) async {
      _pinInstallChannel(InstallKind.sideload);
      await _pumpSupportSheet(tester);

      for (final text in find
          .byType(Text)
          .evaluate()
          .map((e) => ((e.widget as Text).data ?? '').toLowerCase())) {
        for (final brand in const [
          'daly',
          'jbd',
          'seplos',
          'tianpower',
          'basen',
          'lolan',
          'topband',
          'offgridtec',
        ]) {
          expect(text, isNot(contains(brand)),
              reason: 'public copy must stay JK-BMS only (found: "$text")');
        }
      }
    });
  });
}
