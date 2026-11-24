import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/models/bms_models.dart';
import 'package:jkbmsr_ble/widgets/battery_hero_card.dart';

// Two defects in the same card, both about showing certainty the data does
// not support:
//   * a BLE link that is up but has produced no frame read as OFFLINE while
//     the app bar said ON;
//   * an empty cell list made max - min zero, so the footer reported a
//     perfectly balanced pack with a green check directly above the banner
//     saying no cell voltages were reported.

BmsStatus _status({List<CellInfo> cells = const [], double currentA = 0}) => BmsStatus(
      soc: 50,
      totalVoltage: 26.4,
      currentA: currentA,
      powerW: currentA * 26.4,
      remainingCapacityAh: 100,
      nominalCapacityAh: 100,
      cycleCount: 1,
      totalCycleCapacityAh: 100,
      cells: cells,
      timestamp: DateTime(2026, 11, 24, 12),
    );

Future<void> _pump(
  WidgetTester tester, {
  required bool isConnected,
  required bool hasLiveData,
  List<CellInfo> cells = const [],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BatteryHeroCard(
            status: _status(cells: cells),
            isConnected: isConnected,
            hasLiveData: hasLiveData,
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('a live link with no frame is waiting for data, not offline', (tester) async {
    await _pump(tester, isConnected: true, hasLiveData: false);

    expect(find.text('WAITING FOR DATA'), findsOneWidget);
    expect(find.text('Waiting for data'), findsOneWidget);
    expect(find.text('OFFLINE'), findsNothing);
    expect(find.text('No device connected'), findsNothing);
  });

  testWidgets('an empty cell list leaves imbalance unknown, not zero and green', (tester) async {
    await _pump(tester, isConnected: true, hasLiveData: true);

    expect(find.text('Cell imbalance: -'), findsOneWidget);
    expect(find.textContaining('Cell imbalance: 0 mV'), findsNothing);
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    expect(find.byIcon(Icons.remove_circle_outline_rounded), findsOneWidget);
  });

  testWidgets('a reported balanced pack still gets the real reading', (tester) async {
    await _pump(
      tester,
      isConnected: true,
      hasLiveData: true,
      cells: const [
        CellInfo(index: 0, voltage: 3.320),
        CellInfo(index: 1, voltage: 3.321),
      ],
    );

    expect(find.text('Cell imbalance: 1 mV'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });
}
