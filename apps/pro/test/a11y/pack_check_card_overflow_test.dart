// The pack check card is new, multi-line, and lives on a phone at the top of
// the Alerts screen. It must survive the OS's largest common text scale on a
// narrow device without an overflow stripe and without hiding the numbers.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jkbmsr_pro/features/alerts/pack_check.dart';
import 'package:jkbmsr_pro/features/alerts/pack_check_card.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

const _longDevice = 'Warehouse Backup Bank — North Wing Array';

Future<void> _pumpCard(
  WidgetTester tester,
  PackCheckReport report, {
  double textScale = 2.0,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: PackCheckCard(report: report),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('findings lay out at textScale 2.0 on a 360dp phone',
      (tester) async {
    const report = PackCheckReport(
      verdict: PackCheckVerdict.findings,
      findings: [
        PackCheckFinding(
          deviceName: _longDevice,
          severity: PackCheckSeverity.critical,
          title: 'Pack temperature is 55.4 °C',
          detail:
              '50 °C is the app\'s own "Hot" boundary. Most LiFePO4 cells are only charged up to 45 °C.',
        ),
        PackCheckFinding(
          deviceName: _longDevice,
          severity: PackCheckSeverity.attention,
          title: 'Cell 12 is 145 mV above cell 3',
          detail:
              'Max 3.455 V · min 3.310 V · spread 145 mV. The cell view calls a pack balanced up to 30 mV.',
        ),
        PackCheckFinding(
          deviceName: _longDevice,
          severity: PackCheckSeverity.attention,
          title: 'Gateway has stopped reporting',
          detail: 'Last upload 2h 46m ago; this gateway reports every 1m.',
        ),
      ],
      coverageNote: '1 of 2 gateways could not be read.',
    );

    await _pumpCard(tester, report);

    expect(tester.takeException(), isNull);
    expect(find.text('Pack check'), findsOneWidget);
    expect(find.text('Pack temperature is 55.4 °C'), findsOneWidget);
    expect(find.textContaining('145 mV'), findsWidgets);
  });

  testWidgets('the no-data state keeps its exact wording at textScale 2.0',
      (tester) async {
    const report = PackCheckReport.noData(
      'Garage pack has not reported telemetry yet.',
    );

    await _pumpCard(tester, report);

    expect(tester.takeException(), isNull);
    expect(find.text('Not enough data to check the pack'), findsOneWidget);
    expect(
      find.text('Garage pack has not reported telemetry yet.'),
      findsOneWidget,
    );
  });

  testWidgets('the clear state lays out at textScale 2.0', (tester) async {
    const report = PackCheckReport(
      verdict: PackCheckVerdict.clear,
      facts: [
        'Garage pack: 16 cells · 8 mV spread · 22.4 °C · 84% charge',
      ],
    );

    await _pumpCard(tester, report);

    expect(tester.takeException(), isNull);
    expect(find.text('The readings that could be checked look normal.'),
        findsOneWidget);
    expect(find.textContaining('8 mV spread'), findsOneWidget);
  });
}
