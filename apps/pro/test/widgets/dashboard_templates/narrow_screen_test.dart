import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/dashboard_templates/classic_dark_template.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/dashboard_templates/gauge_sparkline_template.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/dashboard_templates/icon_tiles_template.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/dashboard_templates/status_pills_template.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/dashboard_templates/terminal_readout_template.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/dashboard_templates/severity_gauge_template.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/dashboard_templates/mosaic_grid_template.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/dashboard_templates/at_a_glance_strip_template.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';
import 'package:jkbmsr_pro/models/telemetry.dart';
import 'package:jkbmsr_pro/models/telemetry_history_point.dart';

// A device reporting long, real-world values on the smallest phone width we
// support (320dp — an iPhone SE 1st-gen/older Android) is exactly what
// produced the RenderFlex overflow ("breaks") a user reported after all 8
// templates shipped: raw Row-of-unconstrained-Text layouts had no way to
// shrink or wrap, so a long label plus its value routinely exceeded the
// available column width. Every template here is mounted at that width with
// telemetry chosen to be as wide as realistically possible, and the test
// fails loudly (via tester.takeException()) if Flutter logs a layout error
// — the same failure mode a real overflow produces.
Widget _wrap(Widget child) {
  return MediaQuery(
    data: const MediaQueryData(size: Size(320, 900)),
    child: MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: Scaffold(body: SingleChildScrollView(child: SizedBox(width: 320, child: child))),
    ),
  );
}

Telemetry _wideTelemetry() {
  return Telemetry(
    voltage: 512.345,
    current: -1234.56,
    power: -123456.7,
    soc: 100,
    temperature1: -12.3,
    temperature2: 123.4,
    cells: [for (var i = 1; i <= 24; i++) CellVoltage(cell: i, voltage: 3.2 + i * 0.01)],
    bms: BmsExtras.fromJson({
      'mosfetTemperature': 123.4,
      'minCellVoltage': 3.1,
      'maxCellVoltage': 3.9,
      'avgCellVoltage': 3.456,
      'deltaCellVoltage': 0.789,
      'cycleCount': 123456,
      'cycleCapacityAh': 123456.78,
      'fullCapacityAh': 12345.6,
      'remainingCapacityAh': 12345.6,
      'stateOfHealth': 100.0,
      'balancingCurrent': 123.45,
      'balancing': true,
      'charging': true,
      'discharging': false,
      'errorsBitmask': 1,
    }),
    diagnostics: const {},
  );
}

List<TelemetryHistoryPoint> _wideHistory() {
  return [
    TelemetryHistoryPoint(timestamp: 't1', voltage: 500.1, current: -1200.0, power: -600600.0),
    TelemetryHistoryPoint(timestamp: 't2', voltage: 512.3, current: -1234.5, power: -632416.0),
    TelemetryHistoryPoint(timestamp: 't3', voltage: 505.6, current: -1180.2, power: -596724.0),
  ];
}

void main() {
  testWidgets('Classic Readout does not overflow at 320dp width with worst-case values', (tester) async {
    await tester.pumpWidget(_wrap(JKBMSRClassicDarkTemplate(telemetry: _wideTelemetry(), lastSeen: '2 minutes ago')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Gauge & Sparkline does not overflow at 320dp width with worst-case values', (tester) async {
    await tester.pumpWidget(_wrap(JKBMSRGaugeSparklineTemplate(telemetry: _wideTelemetry(), lastSeen: '2 minutes ago', history: _wideHistory())));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Icon Tiles does not overflow at 320dp width with worst-case values', (tester) async {
    await tester.pumpWidget(_wrap(JKBMSRIconTilesTemplate(telemetry: _wideTelemetry(), lastSeen: '2 minutes ago', history: _wideHistory())));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Status Pills does not overflow at 320dp width with worst-case values', (tester) async {
    await tester.pumpWidget(_wrap(JKBMSRStatusPillsTemplate(
      telemetry: _wideTelemetry(),
      deviceName: 'A Very Long Gateway Name That Keeps Going',
      deviceStatus: 'online',
      lastSeen: '2 minutes ago',
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Terminal Readout does not overflow at 320dp width with worst-case values', (tester) async {
    await tester.pumpWidget(_wrap(JKBMSRTerminalReadoutTemplate(
      telemetry: _wideTelemetry(),
      deviceStatus: 'online',
      lastSeen: '2 minutes ago',
      history: _wideHistory(),
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Severity Gauge does not overflow at 320dp width with worst-case values', (tester) async {
    await tester.pumpWidget(_wrap(JKBMSRSeverityGaugeTemplate(telemetry: _wideTelemetry(), lastSeen: '2 minutes ago')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mosaic Grid does not overflow at 320dp width with worst-case values', (tester) async {
    await tester.pumpWidget(_wrap(JKBMSRMosaicGridTemplate(telemetry: _wideTelemetry(), lastSeen: '2 minutes ago')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('At-a-Glance Strip does not overflow at 320dp width with worst-case values', (tester) async {
    await tester.pumpWidget(_wrap(JKBMSRAtAGlanceStripTemplate(
      telemetry: _wideTelemetry(),
      deviceName: 'A Very Long Gateway Name That Keeps Going',
      deviceStatus: 'online',
      lastSeen: '2 minutes ago',
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
