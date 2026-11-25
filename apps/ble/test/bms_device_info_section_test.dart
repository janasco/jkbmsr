import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/models/bms_parameter.dart';
import 'package:jkbmsr_ble/widgets/bms_device_info_section.dart';
import 'package:jkbmsr_ble/widgets/motion_kit.dart';

import 'support/test_fonts.dart';

void main() {
  setUpAll(loadMonospaceTestFont);

  testWidgets('device-info panel renders the decoded identity fields', (tester) async {
    const info = BmsModelInfo(
      modelName: 'JK-B2A24S15P',
      hardwareVersion: '10.XW',
      softwareVersion: '10.07',
      serialNumber: '2021602096',
      manufacturingDate: '2022-04-07',
      uptimeSeconds: 110400,
      powerOnCount: 6,
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BmsDeviceInfoSection(info: info, isConnected: true)),
    ));

    expect(find.text('JK-B2A24S15P'), findsOneWidget);
    expect(find.text('10.XW'), findsOneWidget);
    expect(find.text('10.07'), findsOneWidget);
    expect(find.text('2021602096'), findsOneWidget);
    expect(find.text('2022-04-07'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('30h 40m'), findsOneWidget); // 110400 s
  });

  testWidgets('device-info panel shows skeletons, never dashes, while connected but not yet decoded',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BmsDeviceInfoSection(info: null, isConnected: true)),
    ));

    // Still waiting for the 0x03 frame: value column is a skeleton, not "-".
    expect(find.byType(JkSkeleton), findsNWidgets(7));
    expect(find.text('-'), findsNothing);
    // The labels stay real, so the panel still reads as pending fields.
    expect(find.text('Model'), findsOneWidget);
    expect(find.text('Serial number'), findsOneWidget);
  });

  testWidgets('device-info panel shows dashes for fields absent from a decoded frame',
      (tester) async {
    // A frame HAS been decoded, but these string fields are empty in it: that
    // is "not present", which must stay "-" and never become a skeleton.
    const info = BmsModelInfo(
      modelName: 'JK-B2A24S15P',
      hardwareVersion: '',
      softwareVersion: '',
      serialNumber: '',
      manufacturingDate: '',
      uptimeSeconds: 0,
      powerOnCount: 0,
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BmsDeviceInfoSection(info: info, isConnected: true)),
    ));

    expect(find.byType(JkSkeleton), findsNothing);
    // hardware, software, serial, manufactured, run time (uptime 0) are all "-".
    expect(find.text('-'), findsNWidgets(5));
    expect(find.text('JK-B2A24S15P'), findsOneWidget);
  });

  testWidgets('device-info panel shows dashes while disconnected even if a stale info exists',
      (tester) async {
    const info = BmsModelInfo(
      modelName: 'JK-B2A24S15P',
      hardwareVersion: '10.XW',
      softwareVersion: '10.07',
      uptimeSeconds: 110400,
      powerOnCount: 6,
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BmsDeviceInfoSection(info: info, isConnected: false)),
    ));

    expect(find.text('JK-B2A24S15P'), findsNothing);
    expect(find.text('-'), findsNWidgets(7));
  });

  group('at 2x text on a 360dp phone', () {
    // 360 dp phone minus 16 dp of page padding, which is the status list's
    // real content width. Inside the card another 14 dp of padding each side
    // leaves ~300 dp for the row.
    Widget wrap(Widget child) => MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2.0),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: child,
                ),
              ),
            ),
          ),
        );

    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('label/value rows wrap instead of overflowing', (tester) async {
      phone(tester);
      const info = BmsModelInfo(
        modelName: 'JK-B2A24S15P',
        hardwareVersion: '10.XW',
        softwareVersion: '10.07',
        serialNumber: '2021602096',
        manufacturingDate: '2022-04-07',
        uptimeSeconds: 110400,
        powerOnCount: 6,
      );

      await tester.pumpWidget(wrap(
        const BmsDeviceInfoSection(info: info, isConnected: true),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Nothing hidden: both halves of the longest row are still laid out.
      expect(find.text('Serial number'), findsOneWidget);
      expect(find.text('2021602096'), findsOneWidget);
      expect(find.text('Hardware version'), findsOneWidget);
      expect(find.text('10.XW'), findsOneWidget);
    });

    testWidgets('skeleton rows wrap instead of overflowing', (tester) async {
      phone(tester);

      await tester.pumpWidget(wrap(
        const BmsDeviceInfoSection(info: null, isConnected: true),
      ));
      // The skeleton bars pulse; a single long-pump is enough to lay out.
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.text('Hardware version'), findsOneWidget);
      expect(find.byType(JkSkeleton), findsNWidgets(7));
    });
  });
}
