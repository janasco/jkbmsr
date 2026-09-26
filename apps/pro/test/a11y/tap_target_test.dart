// Accessibility device pass: every tappable control must expose a hit area of
// at least 48x48dp (primary navigation) or 44x44dp (secondary controls).
//
// The Android emulator/KVM is not available on this machine, so these widget
// tests are the executable substitute: they enable the semantics tree, walk
// every node that is a button / has a tap action, and fail with the full list
// of undersized controls rather than stopping at the first one.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/app/app.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/components.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

import 'a11y_support.dart';

Widget _shell(String route) {
  return MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    home: JKBMSRShellLayout(
      currentRoute: route,
      onNavigate: (_) {},
      child: const SizedBox.shrink(),
    ),
  );
}

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('primary navigation', () {
    testWidgets('phone shell (bottom nav + app-bar actions) exposes >=48dp targets', (tester) async {
      _setSize(tester, const Size(400, 800));

      await tester.pumpWidget(_shell('/dashboard?deviceId=gw-1'));
      await tester.pumpAndSettle();

      await expectTapTargetsAtLeast(tester, minSize: 48, where: 'Phone shell (bottom nav)');
    });

    testWidgets('tablet shell (sidebar) exposes >=48dp targets', (tester) async {
      _setSize(tester, const Size(1024, 800));

      await tester.pumpWidget(_shell('/dashboard?deviceId=gw-1'));
      await tester.pumpAndSettle();

      await expectTapTargetsAtLeast(tester, minSize: 48, where: 'Tablet shell (sidebar)');
    });
  });

  group('reusable controls', () {
    testWidgets('tabs expose >=48dp targets', (tester) async {
      _setSize(tester, const Size(400, 800));

      await tester.pumpWidget(MaterialApp(
        theme: JKBMSRTheme.darkTheme,
        home: Scaffold(
          body: JKBMSRTabs(
            tabTitles: const ['Overview', 'Cells', 'Alerts'],
            selectedIndex: 0,
            onTabSelected: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await expectTapTargetsAtLeast(tester, minSize: 48, where: 'Tabs');
    });

    testWidgets('segmented control exposes >=48dp targets', (tester) async {
      _setSize(tester, const Size(400, 800));

      await tester.pumpWidget(MaterialApp(
        theme: JKBMSRTheme.darkTheme,
        home: Scaffold(
          body: JKBMSRSegmentedControl<String>(
            options: const {'today': 'Today', 'week': 'Week', 'month': 'Month'},
            selectedValue: 'today',
            onSelected: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await expectTapTargetsAtLeast(tester, minSize: 48, where: 'Segmented control');
    });

    testWidgets('pagination exposes >=48dp targets', (tester) async {
      _setSize(tester, const Size(400, 800));

      await tester.pumpWidget(MaterialApp(
        theme: JKBMSRTheme.darkTheme,
        home: Scaffold(
          body: JKBMSRPagination(
            currentPage: 2,
            totalPages: 5,
            onPrevious: () {},
            onNext: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await expectTapTargetsAtLeast(tester, minSize: 48, where: 'Pagination');
    });
  });
}
