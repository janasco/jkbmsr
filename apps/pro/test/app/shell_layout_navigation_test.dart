import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/app/app.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

Widget _wrap(String currentRoute, ValueChanged<String> onNavigate) {
  return MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    home: JKBMSRShellLayout(
      currentRoute: currentRoute,
      onNavigate: onNavigate,
      child: const SizedBox.shrink(),
    ),
  );
}

void main() {
  group('phone width (bottom nav)', () {
    testWidgets('switching to a device-scoped tab carries the current deviceId forward', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      String? navigatedTo;
      await tester.pumpWidget(_wrap('/dashboard?deviceId=gw-1', (route) => navigatedTo = route));

      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pumpAndSettle();

      expect(navigatedTo, '/cells?deviceId=gw-1');
    });

    testWidgets('switching to Alerts does not carry a deviceId (account-wide, not per-gateway)', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      String? navigatedTo;
      await tester.pumpWidget(_wrap('/dashboard?deviceId=gw-1', (route) => navigatedTo = route));

      await tester.tap(find.byIcon(Icons.notifications_none));
      await tester.pumpAndSettle();

      expect(navigatedTo, '/alerts');
    });

    testWidgets('navigating with no deviceId in the current route omits the query param', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      String? navigatedTo;
      await tester.pumpWidget(_wrap('/dashboard', (route) => navigatedTo = route));

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(navigatedTo, '/settings');
    });
  });

  group('tablet width (sidebar)', () {
    testWidgets('switching tabs via the sidebar carries the current deviceId forward', (tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      String? navigatedTo;
      await tester.pumpWidget(_wrap('/dashboard?deviceId=gw-1', (route) => navigatedTo = route));

      await tester.tap(find.widgetWithText(ListTile, 'Cell Voltages'));
      await tester.pumpAndSettle();

      expect(navigatedTo, '/cells?deviceId=gw-1');
    });

    testWidgets('switching to Gateways via the sidebar does not carry a deviceId', (tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      String? navigatedTo;
      await tester.pumpWidget(_wrap('/dashboard?deviceId=gw-1', (route) => navigatedTo = route));

      await tester.tap(find.widgetWithText(ListTile, 'Gateways'));
      await tester.pumpAndSettle();

      expect(navigatedTo, '/devices');
    });
  });
}
