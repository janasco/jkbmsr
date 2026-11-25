import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/models/bms_models.dart';
import 'package:jkbmsr_ble/widgets/cell_voltages_section.dart';
import 'package:jkbmsr_ble/widgets/wire_resistance_section.dart';

import '../support/test_fonts.dart';

// The widget-level half of the adaptive-grid rule: the column count the two
// matrices actually lay out with, measured from the live SliverGridDelegate
// at a real 328 dp content width (360 dp phone minus 16 dp page padding).

List<CellInfo> _cells() => [
      for (var i = 1; i <= 24; i++)
        CellInfo(
          index: i,
          voltage: 3.2 + i * 0.003,
          wireResistance: 0.1 + i * 0.01,
        ),
    ];

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required double textScale,
}) async {
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
            child: child,
          ),
        ),
      ),
    ),
  ));
  // PulseGlow (the MIN/MAX badges) animates forever, so settle would time out.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

int _columns(WidgetTester tester) {
  final grid = tester.widget<GridView>(find.byType(GridView));
  final delegate = grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
  return delegate.crossAxisCount;
}

void main() {
  setUpAll(loadMonospaceTestFont);

  group('cell matrix column count', () {
    testWidgets('Cell Voltages uses four columns at 1x on 328 dp',
        (tester) async {
      await _pump(tester, CellVoltagesSection(cells: _cells()), textScale: 1.0);
      expect(_columns(tester), 4);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Cell Voltages sheds to two columns at 2x on 328 dp',
        (tester) async {
      await _pump(tester, CellVoltagesSection(cells: _cells()), textScale: 2.0);
      expect(_columns(tester), 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Cell Voltages sheds to one column at 3x on 328 dp',
        (tester) async {
      await _pump(tester, CellVoltagesSection(cells: _cells()), textScale: 3.0);
      expect(_columns(tester), 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Wire Resistance uses four columns at 1x on 328 dp',
        (tester) async {
      await _pump(tester, WireResistanceSection(cells: _cells()),
          textScale: 1.0);
      expect(_columns(tester), 4);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Wire Resistance sheds to two columns at 2x on 328 dp',
        (tester) async {
      await _pump(tester, WireResistanceSection(cells: _cells()),
          textScale: 2.0);
      expect(_columns(tester), 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Wire Resistance sheds to one column at 3x on 328 dp',
        (tester) async {
      await _pump(tester, WireResistanceSection(cells: _cells()),
          textScale: 3.0);
      expect(_columns(tester), 1);
      expect(tester.takeException(), isNull);
    });
  });
}
