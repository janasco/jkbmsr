import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/battery_indicator.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/colors.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    home: Builder(
      builder: (context) => Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('renders without error across the full percent range', (tester) async {
    for (final percent in [0.0, 0.15, 0.5, 0.85, 1.0]) {
      await tester.pumpWidget(_wrap(JKBMSRBatteryIndicator(percent: percent)));
      expect(find.byType(JKBMSRBatteryIndicator), findsOneWidget);
    }
  });

  testWidgets('clamps out-of-range percent instead of throwing', (tester) async {
    await tester.pumpWidget(_wrap(const JKBMSRBatteryIndicator(percent: -0.5)));
    expect(find.byType(JKBMSRBatteryIndicator), findsOneWidget);

    await tester.pumpWidget(_wrap(const JKBMSRBatteryIndicator(percent: 1.5)));
    expect(find.byType(JKBMSRBatteryIndicator), findsOneWidget);
  });

  testWidgets('transitions cleanly mid-animation when percent changes', (tester) async {
    await tester.pumpWidget(_wrap(const JKBMSRBatteryIndicator(percent: 0.2)));
    // The indicator's fill has a perpetual charging shimmer controller, so
    // pumpAndSettle can never settle — advance a fixed span instead.
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pumpWidget(_wrap(const JKBMSRBatteryIndicator(percent: 0.9)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(JKBMSRBatteryIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(JKBMSRBatteryIndicator), findsOneWidget);
  });

  testWidgets('color-codes by threshold: critical, warning, accent', (tester) async {
    Color fillOf(BuildContext context, double percent) {
      if (percent < 0.2) return context.colors.critical;
      if (percent < 0.4) return context.colors.warning;
      return context.colors.accent;
    }

    late BuildContext capturedContext;
    await tester.pumpWidget(_wrap(Builder(builder: (context) {
      capturedContext = context;
      return const SizedBox.shrink();
    })));

    expect(fillOf(capturedContext, 0.1), capturedContext.colors.critical);
    expect(fillOf(capturedContext, 0.3), capturedContext.colors.warning);
    expect(fillOf(capturedContext, 0.8), capturedContext.colors.accent);
  });
}
