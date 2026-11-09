import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/features/battery/cell_insight.dart';
import 'package:jkbmsr_pro/features/battery/widgets/cell_insight_panel.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

/// Registers the app's bundled faces so the overflow checks measure the
/// typeface that actually ships, not the widget-test placeholder metrics.
Future<void> _loadBundledFonts() async {
  Future<void> load(String family, List<String> faces) async {
    final loader = FontLoader(family);
    for (final face in faces) {
      final bytes = File('assets/fonts/$face').readAsBytesSync();
      loader.addFont(
        Future.value(ByteData.sublistView(Uint8List.fromList(bytes))),
      );
    }
    await loader.load();
  }

  await load('IBMPlexSans', [
    'IBMPlexSans-Regular.ttf',
    'IBMPlexSans-Medium.ttf',
    'IBMPlexSans-SemiBold.ttf',
    'IBMPlexSans-Bold.ttf',
  ]);
  await load('IBMPlexMono', [
    'IBMPlexMono-Regular.ttf',
    'IBMPlexMono-Medium.ttf',
    'IBMPlexMono-Bold.ttf',
  ]);
}

Widget _wrap(Widget child, {double textScale = 1.0}) {
  return MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          // Mirrors the Cell Voltages screen's ListView padding, so the panel
          // is measured at the width it actually gets on a 360 dp phone.
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

void _phoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadBundledFonts();
  });

  testWidgets('renders the spread line and its meaning', (tester) async {
    final insight = describeCells(const [
      CellReading(cell: 1, voltage: 3.297),
      CellReading(cell: 2, voltage: 3.292),
      CellReading(cell: 3, voltage: 3.297),
      CellReading(cell: 4, voltage: 3.297),
      CellReading(cell: 5, voltage: 3.305),
    ])!;

    await tester.pumpWidget(_wrap(CellInsightPanel(insight: insight)));

    expect(
      find.text('Spread 13 mV · weakest cell #2, strongest #5'),
      findsOneWidget,
    );
    expect(find.text('Within the balanced range'), findsOneWidget);
  });

  testWidgets('renders nothing when there is no insight', (tester) async {
    await tester.pumpWidget(_wrap(const CellInsightPanel(insight: null)));

    expect(find.byType(Text), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an imbalanced pack at textScale 2.0 does not overflow',
      (tester) async {
    _phoneViewport(tester);
    const insight = CellInsight(
      cellCount: 32,
      spreadMv: 9999,
      weakestCell: 32,
      strongestCell: 11,
      band: CellSpreadBand.checkCells,
      balancing: true,
      balancingCurrentAmps: 123.45,
    );

    await tester.pumpWidget(_wrap(
      const CellInsightPanel(insight: insight),
      textScale: 2.0,
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('check cells'), findsOneWidget);
    expect(find.textContaining('balancing at 123.45 A'), findsOneWidget);
  });

  testWidgets('a balanced pack at textScale 2.0 does not overflow',
      (tester) async {
    _phoneViewport(tester);
    const insight = CellInsight(
      cellCount: 32,
      spreadMv: 30,
      weakestCell: 32,
      strongestCell: 11,
      band: CellSpreadBand.balanced,
      balancing: false,
      balancingCurrentAmps: 0,
    );

    await tester.pumpWidget(_wrap(
      const CellInsightPanel(insight: insight),
      textScale: 2.0,
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Within the balanced range'), findsOneWidget);
  });
}
