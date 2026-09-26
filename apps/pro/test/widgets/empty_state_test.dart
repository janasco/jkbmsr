import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/components.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

void main() {
  testWidgets('JKBMSREmptyState shows title, description, and optional action', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: JKBMSRTheme.darkTheme,
        home: Scaffold(
          body: JKBMSREmptyState(
            icon: Icons.battery_alert_outlined,
            title: 'No devices found',
            description: 'You have not added any gateway monitors yet.',
            action: ElevatedButton(
              onPressed: () => tapped = true,
              child: const Text('Pair ESP32 Gateway'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('No devices found'), findsOneWidget);
    expect(find.text('You have not added any gateway monitors yet.'), findsOneWidget);

    await tester.tap(find.text('Pair ESP32 Gateway'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('JKBMSREmptyState omits the action area when none is given', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: JKBMSRTheme.darkTheme,
        home: const Scaffold(
          body: JKBMSREmptyState(
            icon: Icons.notifications_off_outlined,
            title: 'No alerts found',
            description: 'Your battery system is operating within healthy parameters.',
          ),
        ),
      ),
    );

    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });
}
