// Device scanner: the scanning state must be visibly animated, and the scan
// control must allow a manual (re)start even while a scan is already running.
//
// There is no BLE stack on the Dart VM, and the base test fake never actually
// starts a scan, so the scan state is driven through
// BleBmsService.debugSetScanningState — the same test-only seam the connection
// state already uses. Without it the scanner could only ever be observed idle.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/main.dart';
import 'package:jkbmsr_ble/screens/devices_screen.dart';
import 'package:jkbmsr_ble/services/ble_service.dart';
import 'package:jkbmsr_ble/widgets/motion_kit.dart';

import 'support/fake_flutter_blue_plus.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: child),
    );

void main() {
  setUp(() {
    installFakeFlutterBluePlus();
    BleBmsService().debugResetScanningState();
    BleBmsService().debugResetConnectionState();
  });
  tearDown(() {
    BleBmsService().debugResetScanningState();
    BleBmsService().debugResetConnectionState();
  });

  testWidgets('idle scanner shows a start control and no radar',
      (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(DevicesScreen(onConnected: () {})));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('SCAN FOR DEVICES'), findsOneWidget);
    expect(find.text('SCAN AGAIN'), findsNothing);
    expect(find.byType(ScanRadar), findsNothing);
    expect(find.byType(JkSkeleton), findsNothing,
        reason: 'an idle scan has no results to wait for, so no skeletons');
  });

  testWidgets('a running scan with no results yet shows skeleton device cards',
      (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    BleBmsService().debugSetScanningState(true);
    await tester.pumpWidget(_wrap(DevicesScreen(onConnected: () {})));
    await tester.pump(const Duration(milliseconds: 300));

    // The radar/label still render, and placeholder cards fill the result area
    // until the first device is found.
    expect(find.byType(ScanRadar), findsWidgets);
    expect(find.byType(JkSkeleton), findsWidgets);
  });

  testWidgets('a running scan shows the radar and the scanning label',
      (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    BleBmsService().debugSetScanningState(true);
    await tester.pumpWidget(_wrap(DevicesScreen(onConnected: () {})));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ScanRadar), findsWidgets);
    expect(find.text('SCAN AGAIN'), findsOneWidget);
    expect(find.text('SCAN FOR DEVICES'), findsNothing);
  });

  testWidgets('the scan control restarts a scan while one is already running',
      (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    BleBmsService().debugSetScanningState(true);
    await tester.pumpWidget(_wrap(DevicesScreen(onConnected: () {})));
    await tester.pump(const Duration(milliseconds: 300));

    final button = find.widgetWithText(FilledButton, 'SCAN AGAIN');
    expect(button, findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull,
        reason: 'the scan control must stay tappable while a scan is running');

    // Tapping it is a manual reload; it must not throw and must leave the
    // control present and enabled.
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.widgetWithText(FilledButton, 'SCAN AGAIN'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'SCAN AGAIN'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('the scan state drives the UI both ways', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(DevicesScreen(onConnected: () {})));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('SCAN FOR DEVICES'), findsOneWidget);

    BleBmsService().debugSetScanningState(true);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('SCAN AGAIN'), findsOneWidget);
    expect(find.byType(ScanRadar), findsWidgets);

    BleBmsService().debugSetScanningState(false);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('SCAN FOR DEVICES'), findsOneWidget);
    expect(find.byType(ScanRadar), findsNothing);
  });

  testWidgets('the top bar no longer carries a three-dot overflow button',
      (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const JkbmsrBleApp());
    await tester.pump(const Duration(milliseconds: 600));

    // The header renders behind the first-run welcome overlay, so it is in the
    // tree without dismissing anything.
    expect(find.byIcon(Icons.more_vert_rounded), findsNothing,
        reason: 'the redundant three-dot header overflow was removed');
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
  });
}
