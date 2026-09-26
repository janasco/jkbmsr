import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/dashboard_templates/classic_dark_template.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';
import 'package:jkbmsr_pro/models/telemetry.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Telemetry _sampleTelemetry() {
  return Telemetry(
    voltage: 52.1,
    current: -12.4,
    power: -646.04,
    soc: 78,
    temperature1: 24.5,
    temperature2: 25.1,
    cells: [CellVoltage(cell: 1, voltage: 3.28), CellVoltage(cell: 2, voltage: 3.31)],
    bms: BmsExtras.fromJson({
      'mosfetTemperature': 26.3,
      'avgCellVoltage': 3.285,
      'deltaCellVoltage': 0.01,
      'cycleCount': 42,
      'cycleCapacityAh': 5200.5,
      'fullCapacityAh': 280,
      'remainingCapacityAh': 218.4,
      'balancingCurrent': 0.35,
      'balancing': true,
      'charging': false,
      'discharging': true,
    }),
    diagnostics: const {},
  );
}

void main() {
  testWidgets('renders headline voltage/current and every metric row', (tester) async {
    await tester.pumpWidget(_wrap(JKBMSRClassicDarkTemplate(telemetry: _sampleTelemetry(), lastSeen: '2m ago')));

    expect(find.text('52.100 V'), findsOneWidget);
    expect(find.text('-12.40 A'), findsOneWidget);
    expect(find.text('78 %'), findsOneWidget);
    expect(find.text('218 Ah'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.textContaining('Balancing'), findsOneWidget);
  });

  testWidgets('falls back to zeroed fields without crashing when telemetry is null', (tester) async {
    await tester.pumpWidget(_wrap(const JKBMSRClassicDarkTemplate(telemetry: null, lastSeen: '')));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('0.000 V'), findsWidgets);
  });
}
