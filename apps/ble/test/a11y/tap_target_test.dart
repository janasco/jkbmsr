// Accessibility device pass: every tappable control must expose a hit area of
// at least 48x48dp (primary navigation) or 44x44dp (secondary controls).
//
// No Android emulator/KVM is available here, so these widget tests are the
// executable substitute: they enable the semantics tree, walk every node that
// is a button / has a tap action, and fail with the full list of undersized
// controls rather than stopping at the first one.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/main.dart';
import 'package:jkbmsr_ble/services/entitlement_service.dart';
import 'package:jkbmsr_ble/widgets/bms_drawer.dart';
import 'package:jkbmsr_ble/widgets/bottom_nav_bar.dart';
import 'package:jkbmsr_ble/widgets/supporter_section.dart';

import '../support/entitlement_test_harness.dart';
import '../support/fake_flutter_blue_plus.dart';
import '../support/fake_in_app_purchase.dart';
import 'a11y_support.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(body: child),
  );
}

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(installFakeFlutterBluePlus);

  group('primary navigation', () {
    testWidgets('bottom nav bar exposes >=48dp targets', (tester) async {
      _setSize(tester, const Size(400, 800));

      await tester.pumpWidget(_wrap(BottomNavBar(
        currentTab: NavTab.status,
        onTabSelect: (_) {},
      )));
      await tester.pumpAndSettle();

      await expectTapTargetsAtLeast(tester, minSize: 48, where: 'Bottom nav bar');
    });

    testWidgets('bottom nav bar exposes >=48dp targets at textScale 2.0', (tester) async {
      _setSize(tester, const Size(400, 800));

      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(
          size: Size(400, 800),
          textScaler: TextScaler.linear(2.0),
        ),
        child: _wrap(BottomNavBar(
          currentTab: NavTab.cells,
          onTabSelect: (_) {},
        )),
      ));
      await tester.pumpAndSettle();

      await expectTapTargetsAtLeast(tester, minSize: 48, where: 'Bottom nav bar (textScale 2.0)');
    });

    testWidgets('drawer exposes >=48dp targets', (tester) async {
      _setSize(tester, const Size(400, 800));

      await tester.pumpWidget(_wrap(BmsDrawer(
        onNavigateToDevices: () {},
        onOpenSoftwareUpdate: () {},
        onOpenSupport: () {},
        onOpenAbout: () {},
      )));
      await tester.pumpAndSettle();

      await expectTapTargetsAtLeast(tester, minSize: 48, where: 'Drawer');
    });

    testWidgets('app header (menu, Bluetooth pill, overflow) exposes >=48dp targets', (tester) async {
      _setSize(tester, const Size(400, 800));

      // Mounts the real app (with the no-op BLE platform from setUp), which
      // is the only way the header row in lib/main.dart is reachable in a
      // widget test. The welcome overlay still renders behind it, so this
      // covers both the first-run buttons and the header controls.
      await tester.pumpWidget(const JkbmsrBleApp());
      await tester.pump(const Duration(milliseconds: 400));

      await expectTapTargetsAtLeast(tester, minSize: 48, where: 'App header');
    });

    testWidgets('support sheet Supporter controls expose >=48dp targets',
        (tester) async {
      _setSize(tester, const Size(400, 900));

      // Mounted on its own (rather than through SupportModal) so the sweep
      // measures the two controls this change adds, not the pre-existing
      // donation buttons in the same sheet.
      installFakePlayBilling(
        installedByPlay: true,
        products: [supporterProduct()],
      );
      EntitlementService.instance.debugOverrideState(
        const EntitlementState(installKind: InstallKind.play, resolved: true),
      );
      addTearDown(EntitlementService.instance.debugResetState);

      await tester.pumpWidget(_wrap(const SupporterSection()));
      await tester.pump(const Duration(milliseconds: 400));

      await expectTapTargetsAtLeast(
        tester,
        minSize: 48,
        where: 'Support sheet (Supporter)',
      );
    });
  });

  group('screens', () {
    testWidgets('Devices screen controls expose >=48dp targets', (tester) async {
      // Deliberately wide: the devices scan header is a spaceBetween Row whose
      // fallback test font is ~2x too wide at 400dp, which produces a phantom
      // RenderFlex overflow that has nothing to do with hit areas. The width
      // does not change any control's minimum size.
      _setSize(tester, const Size(900, 900));

      await tester.pumpWidget(const JkbmsrBleApp());
      await tester.pump(const Duration(milliseconds: 600));

      // Dismiss the first-run welcome overlay so the main scaffold is live.
      final start = find.text('START SCANNING');
      if (start.evaluate().isNotEmpty) {
        await tester.tap(start);
        await tester.pump(const Duration(milliseconds: 600));
      }
      final devicesTab = find.text('DEVICES');
      if (devicesTab.evaluate().isNotEmpty) {
        await tester.tap(devicesTab.last);
        await tester.pump(const Duration(milliseconds: 500));
      }

      await expectTapTargetsAtLeast(tester, minSize: 48, where: 'Devices screen');
    });
  });
}
