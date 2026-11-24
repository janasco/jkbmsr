import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/models/bms_models.dart';
import 'package:jkbmsr_ble/widgets/alerts_section.dart';

// Only wire resistance and cell count are decoded into BmsAlarms. The panel
// used to call an empty flag set "All systems normal" and "ALL CLEAR", which
// read as a full safety statement about a pack whose over-voltage alarm was
// never decoded at all. The copy now names the checks that ran, and says the
// rest is not decoded.

BmsStatus _status() => BmsStatus(
      soc: 50,
      totalVoltage: 26.4,
      currentA: 0,
      powerW: 0,
      remainingCapacityAh: 100,
      nominalCapacityAh: 100,
      cycleCount: 1,
      totalCycleCapacityAh: 100,
      cells: const [],
      timestamp: DateTime(2026, 11, 24, 12),
    );

void main() {
  testWidgets('an empty flag set names the checks that actually ran', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlertsSection(status: _status(), isConnected: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.textContaining('Wire resistance'), findsOneWidget);
    expect(find.textContaining('cell count'), findsOneWidget);
    expect(find.textContaining('not decoded'), findsOneWidget);

    // The two over-claims this panel used to make.
    expect(find.text('All systems normal'), findsNothing);
    expect(find.text('ALL CLEAR'), findsNothing);
    expect(find.textContaining('No active alarms'), findsNothing);
  });
}
