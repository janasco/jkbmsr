import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/models/bms_parameter.dart';
import 'package:jkbmsr_ble/widgets/bms_device_info_section.dart';

void main() {
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

  testWidgets('device-info panel shows dashes, never placeholder values, when nothing decoded',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BmsDeviceInfoSection(info: null, isConnected: true)),
    ));

    expect(find.text('JK-B2A24S15P'), findsNothing);
    expect(find.text('—'), findsNWidgets(7));
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
    expect(find.text('—'), findsNWidgets(7));
  });
}
