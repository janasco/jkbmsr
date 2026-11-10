import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/features/battery/cell_detail.dart';
import 'package:jkbmsr_pro/features/battery/cell_insight.dart';
import 'package:jkbmsr_pro/features/battery/widgets/cell_detail_sheet.dart';
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
        child: Scaffold(body: child),
      ),
    ),
  );
}

void _phoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

List<CellReading> _pack() => const [
      CellReading(cell: 1, voltage: 3.297),
      CellReading(cell: 2, voltage: 3.292),
      CellReading(cell: 3, voltage: 3.297),
      CellReading(cell: 4, voltage: 3.297),
      CellReading(cell: 5, voltage: 3.305),
    ];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadBundledFonts();
  });

  testWidgets('a weakest cell reads against the pack it sits in', (tester) async {
    final detail = describeCell(
      _pack(),
      index: 1,
      balancing: true,
      balancingCurrentAmps: 0.05,
    )!;

    await tester.pumpWidget(_wrap(CellDetailSheet(detail: detail)));

    expect(find.text('Cell 2'), findsOneWidget);
    expect(find.text('3.292 V'), findsOneWidget);
    expect(find.text('Weakest cell in the pack'), findsOneWidget);
    expect(find.text('Deviation'), findsOneWidget);
    expect(find.text('6 mV below average'), findsOneWidget);
    expect(find.text('Pack average'), findsOneWidget);
    expect(find.text('3.298 V'), findsOneWidget);
    expect(find.text('Pack spread'), findsOneWidget);
    expect(find.text('13 mV · Balanced'), findsOneWidget);
    expect(find.text('Balancing'), findsOneWidget);
    expect(find.text('0.05 A'), findsOneWidget);
  });

  testWidgets('a middle cell has no extreme label', (tester) async {
    final detail = describeCell(_pack(), index: 2)!;

    await tester.pumpWidget(_wrap(CellDetailSheet(detail: detail)));

    expect(find.text('Cell 3'), findsOneWidget);
    expect(find.textContaining('cell in the pack'), findsNothing);
    expect(find.textContaining('voltage in the pack'), findsNothing);
    expect(find.text('Idle'), findsOneWidget);
  });

  testWidgets('says there is no per-cell history rather than implying a chart',
      (tester) async {
    final detail = describeCell(_pack(), index: 1)!;

    await tester.pumpWidget(_wrap(CellDetailSheet(detail: detail)));

    expect(find.text(CellDetailSheet.noHistoryTitle), findsOneWidget);
    expect(find.text(CellDetailSheet.noHistoryBody), findsOneWidget);
  });

  testWidgets('a phone at textScale 2.0 does not overflow', (tester) async {
    _phoneViewport(tester);
    final detail = describeCell(
      _pack(),
      index: 1,
      balancing: true,
      balancingCurrentAmps: 123.45,
    )!;

    await tester.pumpWidget(_wrap(
      CellDetailSheet(detail: detail),
      textScale: 2.0,
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Weakest cell in the pack'), findsOneWidget);
  });

  testWidgets('the real modal fits a phone at textScale 2.0', (tester) async {
    _phoneViewport(tester);
    final detail = describeCell(
      _pack(),
      index: 1,
      balancing: true,
      balancingCurrentAmps: 123.45,
    )!;

    await tester.pumpWidget(MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2.0),
          ),
          child: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showCellDetailSheet(context, detail),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No per-cell history'), findsOneWidget);
  });
}
