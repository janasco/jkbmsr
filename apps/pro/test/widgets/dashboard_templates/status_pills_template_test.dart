import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/dashboard_templates/status_pills_template.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';
import 'package:jkbmsr_pro/models/telemetry.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Telemetry _telemetry({int errorsBitmask = 0}) {
  return Telemetry(
    voltage: 52.1,
    current: -12.4,
    power: -646.04,
    soc: 78,
    temperature1: 24.5,
    temperature2: 25.1,
    cells: const [],
    bms: BmsExtras.fromJson({'errorsBitmask': errorsBitmask, 'stateOfHealth': 97}),
    diagnostics: const {},
  );
}

void main() {
  testWidgets('shows OK when there are no BMS errors', (tester) async {
    await tester.pumpWidget(_wrap(JKBMSRStatusPillsTemplate(
      telemetry: _telemetry(),
      deviceName: 'Main Bank',
      deviceStatus: 'online',
      lastSeen: '2m ago',
    )));
    expect(find.text('OK'), findsOneWidget);
    expect(find.text('Error'), findsNothing);
    expect(find.text('Online'), findsOneWidget);
  });

  testWidgets('shows Error when the BMS reports a non-zero errors bitmask', (tester) async {
    await tester.pumpWidget(_wrap(JKBMSRStatusPillsTemplate(
      telemetry: _telemetry(errorsBitmask: 1),
      deviceName: 'Main Bank',
      deviceStatus: 'offline',
      lastSeen: '2m ago',
    )));
    expect(find.text('Error'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
  });
}
