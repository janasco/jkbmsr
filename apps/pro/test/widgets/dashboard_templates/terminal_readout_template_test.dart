import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/dashboard_templates/terminal_readout_template.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';
import 'package:jkbmsr_pro/models/telemetry.dart';
import 'package:jkbmsr_pro/models/telemetry_history_point.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Telemetry _telemetry() {
  return Telemetry(
    voltage: 52.1,
    current: -12.4,
    power: -646.04,
    soc: 78,
    temperature1: 24.5,
    temperature2: 25.1,
    cells: const [],
    bms: BmsExtras.fromJson(const {}),
    diagnostics: const {},
  );
}

void main() {
  testWidgets('shows STANDBY under the gauge for an online device', (tester) async {
    await tester.pumpWidget(_wrap(JKBMSRTerminalReadoutTemplate(
      telemetry: _telemetry(),
      deviceStatus: 'online',
      lastSeen: '2m ago',
      history: const [],
    )));
    expect(find.text('STANDBY'), findsOneWidget);
    expect(find.text('OFFLINE'), findsNothing);
  });

  testWidgets('shows OFFLINE under the gauge for an offline device', (tester) async {
    await tester.pumpWidget(_wrap(JKBMSRTerminalReadoutTemplate(
      telemetry: _telemetry(),
      deviceStatus: 'offline',
      lastSeen: '2m ago',
      history: [
        TelemetryHistoryPoint(timestamp: 't1', voltage: 51.8, current: -10.0, power: -520.0),
        TelemetryHistoryPoint(timestamp: 't2', voltage: 52.1, current: -12.4, power: -646.0),
      ],
    )));
    expect(find.text('OFFLINE'), findsOneWidget);
  });
}
