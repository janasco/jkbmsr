import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/cell_voltage_grid.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';
import 'package:jkbmsr_pro/models/telemetry.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  testWidgets('shows an empty-state message when there are no cells', (tester) async {
    await tester.pumpWidget(_wrap(const JKBMSRCellVoltageGrid(cells: [])));
    expect(find.text('No cell telemetry data yet.'), findsOneWidget);
    expect(find.textContaining('V'), findsNothing);
  });

  testWidgets('renders one tile per cell with its voltage', (tester) async {
    final cells = [
      CellVoltage(cell: 1, voltage: 3.28),
      CellVoltage(cell: 2, voltage: 3.31),
      CellVoltage(cell: 3, voltage: 3.29),
    ];
    await tester.pumpWidget(_wrap(JKBMSRCellVoltageGrid(cells: cells)));

    expect(find.text('3.280 V'), findsOneWidget);
    expect(find.text('3.310 V'), findsOneWidget);
    expect(find.text('3.290 V'), findsOneWidget);
  });

  testWidgets('computes max/min/imbalance summary from the given cells', (tester) async {
    final cells = [
      CellVoltage(cell: 1, voltage: 3.20),
      CellVoltage(cell: 2, voltage: 3.35),
    ];
    await tester.pumpWidget(_wrap(JKBMSRCellVoltageGrid(cells: cells)));

    expect(find.text('3.350V'), findsOneWidget); // Max Cell
    expect(find.text('3.200V'), findsOneWidget); // Min Cell
    expect(find.text('150mV'), findsOneWidget); // Imbalance: (3.35 - 3.20) * 1000
  });

  testWidgets('a tappable row reports its own cell from a 48dp target', (tester) async {
    final cells = [
      CellVoltage(cell: 1, voltage: 3.28),
      CellVoltage(cell: 2, voltage: 3.31),
      CellVoltage(cell: 3, voltage: 3.29),
    ];
    CellVoltage? tapped;
    await tester.pumpWidget(_wrap(JKBMSRCellVoltageGrid(
      cells: cells,
      onCellTap: (cell) => tapped = cell,
    )));

    final target = find.ancestor(
      of: find.text('3.310 V'),
      matching: find.byType(InkWell),
    );
    expect(target, findsOneWidget);
    expect(tester.getSize(target).height, greaterThanOrEqualTo(48.0));

    await tester.tap(find.text('3.310 V'));
    await tester.pump();

    expect(tapped, same(cells[1]));
  });

  testWidgets('rows are not interactive when no tap handler is given', (tester) async {
    await tester.pumpWidget(_wrap(JKBMSRCellVoltageGrid(
      cells: [
        CellVoltage(cell: 1, voltage: 3.28),
        CellVoltage(cell: 2, voltage: 3.31),
      ],
    )));

    expect(find.byType(InkWell), findsNothing);
  });
}
