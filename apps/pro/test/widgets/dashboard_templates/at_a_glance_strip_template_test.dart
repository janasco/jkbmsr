import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/dashboard_templates/at_a_glance_strip_template.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';
import 'package:jkbmsr_pro/models/telemetry.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Telemetry _telemetry() {
  return Telemetry(
    voltage: 52.1,
    current: -12.4,
    power: -646.04,
    soc: 78,
    temperature1: 24.5,
    temperature2: 25.1,
    cells: const [],
    bms: BmsExtras.fromJson(const {}),
    diagnostics: const {},
  );
}

void main() {
  testWidgets('renders all four stacked panels', (tester) async {
    await tester.pumpWidget(_wrap(JKBMSRAtAGlanceStripTemplate(
      telemetry: _telemetry(),
      deviceName: 'Main Bank',
      deviceStatus: 'online',
      lastSeen: '2m ago',
    )));
    expect(find.text('STATUS'), findsOneWidget);
    expect(find.text('ELECTRICALS'), findsOneWidget);
    expect(find.text('CELLS'), findsOneWidget);
    expect(find.text('THERMAL'), findsOneWidget);
    expect(find.text('Main Bank'), findsOneWidget);
  });
}
