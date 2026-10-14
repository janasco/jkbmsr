import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/widgets/plan_pill.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.dark}) {
  return MaterialApp(
    theme: brightness == Brightness.dark ? JKBMSRTheme.darkTheme : JKBMSRTheme.lightTheme,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('formatPlanInterval', () {
    test('formats the documented cases', () {
      expect(formatPlanInterval(3600), '1 hr');
      expect(formatPlanInterval(300), '5 min');
      expect(formatPlanInterval(60), '1 min');
      expect(formatPlanInterval(30), '30 sec');
      expect(formatPlanInterval(900), '15 min');
      expect(formatPlanInterval(1800), '30 min');
    });
  });

  testWidgets('renders the tier label and interval', (tester) async {
    await tester.pumpWidget(_wrap(const PlanPill(
      tierLabel: 'Entry',
      intervalSeconds: 300,
      status: 'active',
    )));

    expect(find.text('Entry · every 5 min'), findsOneWidget);
  });

  testWidgets('defaults to the inactive styling', (tester) async {
    await tester.pumpWidget(_wrap(const PlanPill(
      tierLabel: 'Free',
      intervalSeconds: 3600,
    )));

    expect(find.text('Free · every 1 hr'), findsOneWidget);
    expect(find.bySemanticsLabel('Free · every 1 hr, inactive plan'), findsOneWidget);
  });

  testWidgets('announces an active plan to screen readers', (tester) async {
    await tester.pumpWidget(_wrap(const PlanPill(
      tierLabel: 'Standard',
      intervalSeconds: 60,
      status: 'active',
    )));

    expect(find.text('Standard · every 1 min'), findsOneWidget);
    expect(find.bySemanticsLabel('Standard · every 1 min, active plan'), findsOneWidget);
  });

  testWidgets('compact renders the same label in a smaller pill', (tester) async {
    await tester.pumpWidget(_wrap(const PlanPill(
      tierLabel: 'Lite',
      intervalSeconds: 900,
      status: 'active',
      compact: true,
    )));

    expect(find.text('Lite · every 15 min'), findsOneWidget);
  });

  testWidgets('renders in both light and dark themes without error', (tester) async {
    await tester.pumpWidget(_wrap(
      const PlanPill(tierLabel: 'Entry', intervalSeconds: 300, status: 'active'),
      brightness: Brightness.light,
    ));
    expect(find.text('Entry · every 5 min'), findsOneWidget);

    await tester.pumpWidget(_wrap(
      const PlanPill(tierLabel: 'Entry', intervalSeconds: 300, status: 'active'),
      brightness: Brightness.dark,
    ));
    expect(find.text('Entry · every 5 min'), findsOneWidget);
  });
}
