// Content-shaped skeleton primitives.
//
// JKBMSRSkeleton is a single pulsing block; screens compose it into the shapes
// of the content that will replace it via JKBMSRSkeletonCard /
// JKBMSRSkeletonListRow / JKBMSRSkeletonStat. These tests lock two properties
// the outlines depend on: the helpers lay out without overflowing on a narrow
// phone at the top accessibility text scale (they are fixed-size shapes, so
// they must never clip), and they still inherit JKBMSRSkeleton's reduced-motion
// behaviour (a static block when the OS asks for no animation) rather than
// animating on their own.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/components.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/tokens.dart';

Widget _app(Widget child) {
  return MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2.0),
        ),
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  testWidgets(
      'content-shaped skeleton helpers lay out without overflow at large text',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(ListView(
      padding: const EdgeInsets.all(JKBMSRTokens.space16),
      children: [
        JKBMSRSkeletonCard(
          children: [
            Row(
              children: const [
                Expanded(child: JKBMSRSkeleton(height: 16)),
                SizedBox(width: JKBMSRTokens.space12),
                JKBMSRSkeleton(
                    width: 64,
                    height: 22,
                    borderRadius: JKBMSRTokens.radiusFull),
              ],
            ),
          ],
        ),
        const SizedBox(height: JKBMSRTokens.space12),
        const JKBMSRSkeletonListRow(),
        const SizedBox(height: JKBMSRTokens.space12),
        const Row(
          children: [
            Expanded(child: JKBMSRSkeletonStat()),
            SizedBox(width: JKBMSRTokens.space12),
            Expanded(child: JKBMSRSkeletonStat(showIcon: false)),
          ],
        ),
      ],
    )));

    await tester.pump(const Duration(milliseconds: 120));

    expect(tester.takeException(), isNull,
        reason: 'the skeleton shapes must not overflow at textScale 2.0');
    // Non-vacuous: the helpers actually render skeleton blocks.
    expect(find.byType(JKBMSRSkeleton), findsWidgets);
  });

  testWidgets('JKBMSRSkeleton is static when the OS disables animations',
      (tester) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
        tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: const Scaffold(body: JKBMSRSkeleton()),
    ));

    // The pulse runs from opacity 0.3 to 0.7 over one second. Under reduced
    // motion the controller never starts, so the block must stay at its start
    // value instead of drifting.
    await tester.pump(const Duration(milliseconds: 500));
    final first = tester.widget<Opacity>(find.byType(Opacity)).opacity;
    expect(first, moreOrLessEquals(0.3, epsilon: 0.001));

    await tester.pump(const Duration(milliseconds: 500));
    final second = tester.widget<Opacity>(find.byType(Opacity)).opacity;
    expect(second, moreOrLessEquals(0.3, epsilon: 0.001));

    // No infinite animation is left scheduling frames.
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
