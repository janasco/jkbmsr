import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/dashboard_templates/gauge_sparkline_template.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';
import 'package:jkbmsr_pro/models/telemetry.dart';
import 'package:jkbmsr_pro/models/telemetry_history_point.dart';

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
    cells: [CellVoltage(cell: 1, voltage: 3.28)],
    bms: BmsExtras.fromJson({'remainingCapacityAh': 218.4, 'fullCapacityAh': 280}),
    diagnostics: const {},
  );
}

void main() {
  testWidgets('renders the voltage/capacity gauge headline and a sparkline given enough history', (tester) async {
    final history = [
      TelemetryHistoryPoint(timestamp: 't1', voltage: 51.8, current: -10.0, power: -520.0),
      TelemetryHistoryPoint(timestamp: 't2', voltage: 52.0, current: -11.0, power: -572.0),
      TelemetryHistoryPoint(timestamp: 't3', voltage: 52.1, current: -12.4, power: -646.0),
    ];
    await tester.pumpWidget(_wrap(JKBMSRGaugeSparklineTemplate(telemetry: _sampleTelemetry(), lastSeen: '2m ago', history: history)));

    expect(find.text('52.100 V'), findsOneWidget);
    expect(find.text('218.4 Ah'), findsOneWidget);
    expect(find.text('78% remaining'), findsOneWidget);
    expect(find.text('Not enough data yet'), findsNothing);
  });

  testWidgets('shows a placeholder instead of a chart when history has fewer than 2 points', (tester) async {
    await tester.pumpWidget(_wrap(JKBMSRGaugeSparklineTemplate(telemetry: _sampleTelemetry(), lastSeen: '2m ago', history: const [])));
    expect(find.text('Not enough data yet'), findsOneWidget);
  });
}
