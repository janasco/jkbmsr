import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/screens/welcome_screen.dart';

/// JKBMSR publicly supports JK-BMS only. The welcome screen is the highest-
/// visibility first-run surface, and it used to enumerate every implemented
/// brand as a support claim. This is the durable guard against that copy
/// creeping back in.
void main() {
  Future<void> pumpWelcome(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: WelcomeScreen(onStartScanning: _noop),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Third-party brand names and marketing fragments that must never render
  /// to a user. Matched case-insensitively against the visible text.
  const forbidden = <String>[
    'Daly',
    'JBD',
    'Jiabaida',
    'Xiaoxiang',
    'Seplos',
    'ANT BMS',
    'Tianpower',
    'Basen',
    'KS48100',
    'Topband',
    'Lolan',
    'Offgridtec',
    'OGT',
    'multi-brand',
    'Multi-Brand',
    'Multi-brand',
  ];

  testWidgets('welcome screen shows JK-BMS support', (tester) async {
    await pumpWelcome(tester);

    expect(find.textContaining('SUPPORTED HARDWARE'), findsOneWidget);
    expect(find.text('JK-BMS'), findsWidgets);
  });

  testWidgets('welcome screen never names an unsupported brand',
      (tester) async {
    await pumpWelcome(tester);

    // Scroll the whole page so off-screen copy is built and laid out too.
    final scrollable = find.byType(SingleChildScrollView);
    expect(scrollable, findsOneWidget);

    for (var i = 0; i < 12; i++) {
      await tester.drag(scrollable, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 60));

      final rendered = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data ?? '')
          .where((s) => s.isNotEmpty)
          .toList();

      for (final text in rendered) {
        for (final term in forbidden) {
          expect(
            text.toLowerCase(),
            isNot(contains(term.toLowerCase())),
            reason: 'welcome screen must not mention "$term" (found in: "$text")',
          );
        }
      }
    }
  });

  testWidgets('welcome screen carries the non-affiliation disclaimer',
      (tester) async {
    await pumpWelcome(tester);
    expect(
      find.textContaining('not affiliated with'),
      findsOneWidget,
    );
  });
}

void _noop() {}
