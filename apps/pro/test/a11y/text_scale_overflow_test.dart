// Accessibility device pass: large-text (dynamic type) overflow audit.
//
// Every widget recently reworked for large-accessibility-text support is
// mounted at textScale 2.0 (the top of the 1.3–2.0 range the OS offers) on a
// narrow phone, with worst-case real-world values. A RenderFlex/layout
// overflow makes Flutter log an exception, which `tester.takeException()`
// surfaces — so the test fails loudly instead of shipping clipped content.
//
// The view is resized with `tester.view.physicalSize` (a MediaQuery above the
// app only changes the inherited value, not the layout constraints the
// render tree actually gets). The text scale is then overridden with a
// MediaQuery *inside* MaterialApp.
//
// Widgets that expect a scrollable context are wrapped in a
// SingleChildScrollView exactly like the existing per-widget tests. That hides
// *vertical* overflow of the outer column, but the overflow-prone parts here
// (the grids) use fixed `mainAxisExtent` heights, so any tile-internal
// overflow is still detected.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/models/telemetry.dart';
import 'package:jkbmsr_pro/models/telemetry_history_point.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/battery_indicator.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/cell_voltage_grid.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/dashboard_templates/icon_tiles_template.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/dashboard_templates/mosaic_grid_template.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

const double _largeTextScale = 2.0;

Widget _wrapScaled(Widget child) {
  return MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(_largeTextScale),
        ),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

void _phoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
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
  group('textScale 2.0 overflow', () {
    testWidgets('Cell Voltage Grid does not overflow', (tester) async {
      _phoneViewport(tester);
      await tester.pumpWidget(_wrapScaled(JKBMSRCellVoltageGrid(
        cells: [
          for (var i = 1; i <= 24; i++) CellVoltage(cell: i, voltage: 3.2 + i * 0.01),
        ],
        isCharging: true,
        animationsEnabled: false,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Icon Tiles dashboard template does not overflow', (tester) async {
      _phoneViewport(tester);
      await tester.pumpWidget(_wrapScaled(JKBMSRIconTilesTemplate(
        telemetry: _wideTelemetry(),
        lastSeen: '2 minutes ago',
        history: _wideHistory(),
        animationsEnabled: false,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Mosaic Grid dashboard template does not overflow', (tester) async {
      _phoneViewport(tester);
      await tester.pumpWidget(_wrapScaled(JKBMSRMosaicGridTemplate(
        telemetry: _wideTelemetry(),
        lastSeen: '2 minutes ago',
        animationsEnabled: false,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Battery indicator does not overflow', (tester) async {
      _phoneViewport(tester);
      await tester.pumpWidget(_wrapScaled(const JKBMSRBatteryIndicator(
        percent: 0.5,
        isCharging: true,
        animationsEnabled: false,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
