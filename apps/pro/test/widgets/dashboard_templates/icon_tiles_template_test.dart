import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/dashboard_templates/icon_tiles_template.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';
import 'package:jkbmsr_pro/models/telemetry.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Telemetry _telemetry({double? stateOfHealth}) {
  return Telemetry(
    voltage: 52.1,
    current: -12.4,
    power: -646.04,
    soc: 78,
    temperature1: 24.5,
    temperature2: 25.1,
    cells: [CellVoltage(cell: 1, voltage: 3.28)],
    bms: BmsExtras.fromJson({
      'remainingCapacityAh': 218.4,
      'fullCapacityAh': 280,
      'stateOfHealth': stateOfHealth,
    }),
    diagnostics: const {},
  );
}

void main() {
  testWidgets('shows a State of Health tile when the BMS reports it', (tester) async {
    await tester.pumpWidget(_wrap(JKBMSRIconTilesTemplate(telemetry: _telemetry(stateOfHealth: 97), lastSeen: '2m ago', history: const [])));
    expect(find.text('State of Health'), findsOneWidget);
    expect(find.text('97%'), findsOneWidget);
  });

  testWidgets('omits the State of Health tile when the transport cannot report it', (tester) async {
    await tester.pumpWidget(_wrap(JKBMSRIconTilesTemplate(telemetry: _telemetry(stateOfHealth: null), lastSeen: '2m ago', history: const [])));
    expect(find.text('State of Health'), findsNothing);
  });
}
