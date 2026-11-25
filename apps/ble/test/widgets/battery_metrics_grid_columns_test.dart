import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/models/bms_models.dart';
import 'package:jkbmsr_ble/widgets/battery_metrics_grid.dart';

import '../support/test_fonts.dart';

// The detail matrix is the one grid whose two-column layout hides information
// at 2x: "AVERAGE CELL VOLTAGE" at 22 px is wider than a half-width tile and
// was ellipsized. It drops to a single column as the text grows, so the label
// is readable rather than abbreviated.

BmsStatus _status() => BmsStatus(
      soc: 87,
      totalVoltage: 53.4,
      currentA: -12.34,
      powerW: -659.1,
      remainingCapacityAh: 243.6,
      nominalCapacityAh: 280,
      cycleCount: 1234,
      totalCycleCapacityAh: 11760.5,
      timestamp: DateTime(2026, 11, 25, 12),
    );

Future<void> _pump(WidgetTester tester, {required double textScale}) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: ThemeData.dark(),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: BatteryMetricsGrid(status: _status(), isConnected: true),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

int _columns(WidgetTester tester) {
  final grid = tester.widget<GridView>(find.byType(GridView));
  final delegate = grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
  return delegate.crossAxisCount;
}

void main() {
  setUpAll(loadMonospaceTestFont);

  testWidgets('Battery details keeps two columns at 1x on 328 dp',
      (tester) async {
    await _pump(tester, textScale: 1.0);
    expect(_columns(tester), 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Battery details drops to one column at 2x on 328 dp',
      (tester) async {
    await _pump(tester, textScale: 2.0);
    expect(_columns(tester), 1);
    expect(tester.takeException(), isNull);
    // The label that was abbreviated at half width is on screen in full.
    expect(find.text('AVERAGE CELL VOLTAGE'), findsOneWidget);
  });

  testWidgets('Battery details stays at one column at 3x on 328 dp',
      (tester) async {
    await _pump(tester, textScale: 3.0);
    expect(_columns(tester), 1);
    expect(tester.takeException(), isNull);
  });
}
