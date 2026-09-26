import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/dashboard_templates/mosaic_grid_template.dart';
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
    cells: const [],
    bms: BmsExtras.fromJson({'remainingCapacityAh': 218.4, 'stateOfHealth': stateOfHealth}),
    diagnostics: const {},
  );
}

void main() {
  testWidgets('renders the hero voltage tile and gauge', (tester) async {
    await tester.pumpWidget(_wrap(JKBMSRMosaicGridTemplate(telemetry: _telemetry(stateOfHealth: 97), lastSeen: '2m ago')));
    expect(find.text('52.10 V'), findsOneWidget);
    expect(find.text('State of Health'), findsOneWidget);
  });

  testWidgets('omits the State of Health tile when the transport cannot report it', (tester) async {
    await tester.pumpWidget(_wrap(JKBMSRMosaicGridTemplate(telemetry: _telemetry(stateOfHealth: null), lastSeen: '2m ago')));
    expect(find.text('State of Health'), findsNothing);
  });
}
