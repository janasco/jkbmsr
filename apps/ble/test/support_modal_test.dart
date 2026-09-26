// The GCash / QRPh "Send Support" card is an external payment method, and
// Google Play's Payments policy forbids a Play-distributed app from leading a
// user to anything other than Play Billing. So the card is sideload-only, and
// this is the guard that keeps it that way: the app is "JKBMSR BLE" (not a
// Supporter edition), the app id is "com.jkbmsr.ble", and the card is hidden
// entirely — not disabled, not greyed out — in a Play build.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

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

void main() {
  tearDown(() => EntitlementService.instance.debugResetState());

  group('Google Play build', () {
    testWidgets('hides the GCash/QRPh card entirely', (tester) async {
      _pinInstallChannel(InstallKind.play);
      await _pumpSupportSheet(tester);

      expect(find.byType(QrImageView), findsNothing,
          reason: 'an external payment method must not appear in a Play build');
      expect(find.text('Send Support'), findsNothing);
      expect(find.textContaining('QRPh'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('offers the Play Supporter unlock instead', (tester) async {
      _pinInstallChannel(InstallKind.play);
      await _pumpSupportSheet(tester);

      expect(find.byType(SupporterSection), findsOneWidget);
      expect(find.text('SUPPORTER'), findsOneWidget);
      expect(find.text('RESTORE PURCHASE'), findsOneWidget);
      // The public donation route is unchanged in a Play build.
      expect(find.text('Donate via Google Play'), findsOneWidget);
      expect(find.text('View donation wall'), findsOneWidget);
    });
  });

  group('sideloaded build', () {
    testWidgets('hides the card when no payment details were supplied',
        (tester) async {
      _pinInstallChannel(InstallKind.sideload);
      await _pumpSupportSheet(tester);

      expect(SupportModal.hasQrPhDetails, isFalse,
          reason: 'a default build must not carry payment details');
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Send Support'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('offers no Play purchase, because there is no Play account',
        (tester) async {
      _pinInstallChannel(InstallKind.sideload);
      await _pumpSupportSheet(tester);

      expect(find.byType(SupporterSection), findsNothing);
      expect(find.text('RESTORE PURCHASE'), findsNothing);
      expect(find.text('Donate via Google Play'), findsOneWidget);
      expect(find.text('View donation wall'), findsOneWidget);
    });
  });

  group('unresolved install channel', () {
    testWidgets('hides the external payment method until it is proven safe',
        (tester) async {
      EntitlementService.instance.debugOverrideState(const EntitlementState());
      await _pumpSupportSheet(tester);

      expect(find.byType(QrImageView), findsNothing);
      expect(find.byType(SupporterSection), findsNothing);
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
