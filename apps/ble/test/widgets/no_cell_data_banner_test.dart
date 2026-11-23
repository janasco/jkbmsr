import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/models/bms_models.dart';
import 'package:jkbmsr_ble/widgets/no_cell_data_banner.dart';

BmsStatus _status({double totalVoltage = 0}) => BmsStatus(
      soc: 0,
      totalVoltage: totalVoltage,
      currentA: 0,
      powerW: 0,
      remainingCapacityAh: 0,
      nominalCapacityAh: 0,
      cycleCount: 0,
      totalCycleCapacityAh: 0,
      cells: const [],
      timestamp: DateTime(2026, 11, 23, 12),
    );

Future<void> _pump(WidgetTester tester, BmsStatus status) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: NoCellDataBanner(status: status))),
  );
}

void main() {
  testWidgets('names the state instead of rendering nothing', (tester) async {
    await _pump(tester, _status());
    expect(find.text('NO CELL VOLTAGES REPORTED'), findsOneWidget);
    expect(find.textContaining('reports no cell voltages'), findsOneWidget);
  });

  testWidgets('a powered pack gets the voltage and the actionable sentence', (tester) async {
    await _pump(tester, _status(totalVoltage: 26.1));
    expect(find.textContaining('26.1 V'), findsOneWidget);
    expect(find.textContaining('balance wires'), findsOneWidget);
    // The bench explanation belongs to the case where the pack may genuinely be
    // unpopulated, so it must not be printed when the pack is clearly powered.
    expect(find.textContaining('that is expected'), findsNothing);
  });

  test('the message never claims a voltage it was not given', () {
    expect(NoCellDataBanner.message(_status()), isNot(contains(' V,')));
    expect(NoCellDataBanner.message(_status(totalVoltage: 51.2)), contains('51.2 V'));
  });
}
