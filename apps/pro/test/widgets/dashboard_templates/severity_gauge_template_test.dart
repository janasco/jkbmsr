import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/dashboard_templates/severity_gauge_template.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';
import 'package:jkbmsr_pro/models/telemetry.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Telemetry _telemetry(double soc) {
  return Telemetry(
    voltage: 52.1,
    current: -12.4,
    power: -646.04,
    soc: soc,
    temperature1: 24.5,
    temperature2: 25.1,
    cells: const [],
    bms: BmsExtras.fromJson(const {'remainingCapacityAh': 218.4}),
    diagnostics: const {},
  );
}

void main() {
  testWidgets('renders the danger-zone legend and headline SoC', (tester) async {
    await tester.pumpWidget(_wrap(JKBMSRSeverityGaugeTemplate(telemetry: _telemetry(78), lastSeen: '2m ago')));
    expect(find.text('78%'), findsOneWidget);
    expect(find.text('Below 20%'), findsOneWidget);
    expect(find.text('Below 50%'), findsOneWidget);
    expect(find.text('50% and up'), findsOneWidget);
  });

  testWidgets('does not throw at the SoC extremes', (tester) async {
    await tester.pumpWidget(_wrap(JKBMSRSeverityGaugeTemplate(telemetry: _telemetry(0), lastSeen: '')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(_wrap(JKBMSRSeverityGaugeTemplate(telemetry: _telemetry(100), lastSeen: '')));
    expect(tester.takeException(), isNull);
  });
}
