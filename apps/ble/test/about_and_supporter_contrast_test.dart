// About modal and Supporter section: low-emphasis copy must follow the theme.
//
// Both widgets carried the dark-theme muted grey (0xFF94A3B8) literally. On the
// light surfaces they render on, that is about 2.3–2.6:1 at 11–12 px. This pins
// the resolved colour to AppColors.textMuted in each theme, the same token the
// update modal uses, so the literal cannot creep back in.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:jkbmsr_ble/services/entitlement_service.dart';
import 'package:jkbmsr_ble/widgets/about_modal.dart';
import 'package:jkbmsr_ble/widgets/supporter_section.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'support/entitlement_test_harness.dart';
import 'support/fake_in_app_purchase.dart';

const _lightMuted = Color(0xFF475569); // AppColors.textMuted on light
const _darkMuted = Color(0xFF94A3B8); // AppColors.textMuted on dark

/// The About body paragraph. The version line above it is accent-coloured on
/// purpose, so it is not this finding.
const _aboutBody =
    'JK BMS Bluetooth connects directly to your JK-BMS Bluetooth module';

Finder _aboutBodyFinder() => find.textContaining(_aboutBody);

Future<void> _pumpAbout(WidgetTester tester, ThemeData theme) async {
  PackageInfo.setMockInitialValues(
    appName: 'JK BMS Bluetooth',
    packageName: 'com.jkbmsr.ble',
    version: '4.17.36',
    buildNumber: '56',
    buildSignature: '',
  );
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(body: AboutModal(onClose: () {})),
  ));
  // StaggerIn runs a finite entrance animation.
  await tester.pump(const Duration(milliseconds: 800));
}

/// Installs a Play-managed channel so SupporterSection renders instead of
/// collapsing to nothing. The widget reads the app-wide singleton, so that is
/// the instance whose state is pinned.
void _pinPlayBuild() {
  installFakePlayBilling(
    installedByPlay: true,
    products: [supporterProduct()],
  );
  EntitlementService.instance.debugOverrideState(
    const EntitlementState(installKind: InstallKind.play, resolved: true),
  );
}

Future<void> _pumpSupporter(WidgetTester tester, ThemeData theme) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: const Scaffold(body: SupporterSection()),
  ));
  // Price resolution is async; a few frames let the offered state land.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  tearDown(() => EntitlementService.instance.debugResetState());

  group('About modal body copy', () {
    testWidgets('light theme resolves to the light muted tone', (tester) async {
      await _pumpAbout(tester, ThemeData.light());
      final finder = _aboutBodyFinder();
      expect(finder, findsOneWidget);
      expect(
        tester.widget<Text>(finder).style!.color,
        _lightMuted,
        reason: 'light-mode body copy must follow the theme, not 0xFF94A3B8',
      );
    });

    testWidgets('dark theme resolves to the dark muted tone', (tester) async {
      await _pumpAbout(tester, ThemeData.dark());
      final finder = _aboutBodyFinder();
      expect(finder, findsOneWidget);
      expect(tester.widget<Text>(finder).style!.color, _darkMuted);
    });
  });

  group('Supporter section body copy', () {
    testWidgets('light theme resolves to the light muted tone', (tester) async {
      _pinPlayBuild();
      await _pumpSupporter(tester, ThemeData.light());
      final finder = find.textContaining('One payment, not a subscription.');
      expect(finder, findsOneWidget);
      expect(
        tester.widget<Text>(finder).style!.color,
        _lightMuted,
        reason: 'light-mode blurb must follow the theme, not 0xFF94A3B8',
      );
    });

    testWidgets('dark theme resolves to the dark muted tone', (tester) async {
      _pinPlayBuild();
      await _pumpSupporter(tester, ThemeData.dark());
      final finder = find.textContaining('One payment, not a subscription.');
      expect(finder, findsOneWidget);
      expect(tester.widget<Text>(finder).style!.color, _darkMuted);
    });

    testWidgets('light theme: the failure message uses the same token',
        (tester) async {
      _pinPlayBuild();
      // The double refuses to start the purchase, which is the path that
      // renders the message under the buttons.
      final platform = InAppPurchasePlatform.instance;
      expect(platform, isA<FakeInAppPurchasePlatform>());
      (platform as FakeInAppPurchasePlatform).buyNonConsumableSucceeds = false;

      await _pumpSupporter(tester, ThemeData.light());
      await tester.tap(find.textContaining('REMOVE ADS'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final finder = find.text('Google Play could not start this purchase.');
      expect(finder, findsOneWidget);
      expect(tester.widget<Text>(finder).style!.color, _lightMuted);
    });
  });
}
