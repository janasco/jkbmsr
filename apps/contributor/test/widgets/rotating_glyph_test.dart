import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_contributor/widgets/rotating_glyph.dart';

/// The capture orb's glyph is driven by progress rather than by a timer. These
/// tests pin the two things that makes true: it advances, and it never draws
/// something outside the declared set.
void main() {
  IconData glyph(WidgetTester tester) => tester
      .widget<Icon>(
        find
            .descendant(of: find.byType(RotatingGlyph), matching: find.byType(Icon))
            .last,
      )
      .icon!;

  Future<void> mount(WidgetTester tester, double progress, {int seed = 3}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RotatingGlyph(progress: progress, seed: seed),
          ),
        ),
      );

  testWidgets('advances as progress advances', (WidgetTester tester) async {
    await mount(tester, 0);
    await tester.pumpAndSettle();
    final start = glyph(tester);

    await mount(tester, 0.5);
    await tester.pumpAndSettle();

    expect(glyph(tester), isNot(start));
  });

  testWidgets('never draws an icon outside the declared set',
      (WidgetTester tester) async {
    for (var step = 0; step <= 10; step++) {
      await mount(tester, step / 10);
      await tester.pumpAndSettle();
      expect(
        RotatingGlyph.defaultIcons,
        contains(glyph(tester)),
        reason: 'progress ${step / 10}',
      );
    }
  });

  testWidgets('the same progress and seed always draw the same icon',
      (WidgetTester tester) async {
    await mount(tester, 0.42);
    await tester.pumpAndSettle();
    final first = glyph(tester);

    // A different tree, so the shuffle runs again from the same seed.
    await tester.pumpWidget(const SizedBox.shrink());
    await mount(tester, 0.42);
    await tester.pumpAndSettle();

    expect(glyph(tester), first);
  });
}
