import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/dashboard_templates/energy_flow_template.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';
import 'package:jkbmsr_pro/models/telemetry.dart';
import 'package:jkbmsr_pro/models/telemetry_history_point.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Telemetry _sampleTelemetry({double current = 12.4, Map<String, dynamic>? bmsJson}) {
  return Telemetry(
    voltage: 52.1,
    current: current,
    power: 646.04,
    soc: 78,
    temperature1: 24.5,
    temperature2: 25.1,
    cells: [CellVoltage(cell: 1, voltage: 3.28)],
    bms: BmsExtras.fromJson(bmsJson ??
        {
          'remainingCapacityAh': 262.3,
          'fullCapacityAh': 280,
          'minCellVoltage': 3.251,
          'maxCellVoltage': 3.281,
          'avgCellVoltage': 3.267,
          'deltaCellVoltage': 0.030,
          'minVoltageCell': 1,
          'maxVoltageCell': 2,
          'charging': true,
          'discharging': false,
        }),
    diagnostics: const {},
  );
}

// NOTE: this template runs a repeating AnimationController (the energy-flow
// wire) whenever animations are enabled — pumpAndSettle() would never settle.
// Use pump() with fixed durations only.
void main() {
  testWidgets('renders the SOC ring, energy flow, stats, trend, and balance strip while charging', (tester) async {
    final history = [
      TelemetryHistoryPoint(timestamp: 't1', voltage: 51.8, current: 10.0, power: 518.0),
      TelemetryHistoryPoint(timestamp: 't2', voltage: 52.0, current: 11.0, power: 572.0),
      TelemetryHistoryPoint(timestamp: 't3', voltage: 52.1, current: 12.4, power: 646.0),
    ];
    await tester.pumpWidget(_wrap(
      JKBMSREnergyFlowTemplate(telemetry: _sampleTelemetry(), lastSeen: '2m ago', history: history),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    // SOC ring headline (animated counter shows the initial value on the
    // first frame) + the Ah breakdown inside the ring.
    expect(find.text('STATE OF CHARGE'), findsOneWidget);
    expect(find.text('78%'), findsOneWidget);
    expect(find.text('262.3 of 280 Ah'), findsOneWidget);

    // Energy flow strip: charging lights the source→pack leg.
    expect(find.text('SOURCE'), findsOneWidget);
    expect(find.text('PACK'), findsOneWidget);
    expect(find.text('LOAD'), findsOneWidget);
    expect(find.text('Charging · +646 W in'), findsOneWidget);

    // Live stats row.
    expect(find.text('VOLTAGE'), findsOneWidget);
    expect(find.text('CURRENT'), findsOneWidget);
    expect(find.text('POWER'), findsOneWidget);
    expect(find.text('52.10 V'), findsOneWidget);
    expect(find.text('12.4 A'), findsOneWidget);
    expect(find.text('charging in'), findsOneWidget);
    expect(find.text('646 W'), findsOneWidget);

    // Voltage trend drawn from 3 history points.
    expect(find.text('VOLTAGE TREND'), findsOneWidget);

    // Cell balance strip with min/avg/max markers.
    expect(find.text('CELL BALANCE'), findsOneWidget);
    expect(find.text('Δ 30 mV · cells 1/2'), findsOneWidget);
    expect(find.text('min 3.251 V'), findsOneWidget);
    expect(find.text('avg 3.267 V'), findsOneWidget);
    expect(find.text('max 3.281 V'), findsOneWidget);
  });

  testWidgets('shows the idle state and omits trend/balance sections with no history and no bms data', (tester) async {
    await tester.pumpWidget(_wrap(
      JKBMSREnergyFlowTemplate(
        telemetry: _sampleTelemetry(current: 0.0, bmsJson: const {}),
        lastSeen: '5m ago',
        history: const [],
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No energy flow right now'), findsOneWidget);
    expect(find.text('idle'), findsOneWidget);

    // No trend section without >= 2 history points, no balance strip when
    // the frame carries no avg cell voltage.
    expect(find.text('VOLTAGE TREND'), findsNothing);
    expect(find.text('CELL BALANCE'), findsNothing);
  });

  testWidgets('renders with animations disabled without throwing', (tester) async {
    await tester.pumpWidget(_wrap(
      JKBMSREnergyFlowTemplate(
        telemetry: _sampleTelemetry(),
        lastSeen: '2m ago',
        history: const [],
        animationsEnabled: false,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Charging · +646 W in'), findsOneWidget);
  });
}
