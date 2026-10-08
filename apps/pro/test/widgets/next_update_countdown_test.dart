import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/next_update_countdown.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    home: Scaffold(body: Center(child: child)),
  );
}

Finder _text(String needle) => find.textContaining(needle, findRichText: true);

void main() {
  testWidgets('renders mm:ss from the API snapshot and ticks down each second', (tester) async {
    // withClock installs the binding's fake clock, which tester.pump advances —
    // so the countdown's clock.now() moves with pumped time instead of wall time.
    await withClock(tester.binding.clock, () async {
      await tester.pumpWidget(_wrap(
        const JKBMSRNextUpdateCountdown(
          secondsUntilNextExpectedCheckIn: 558, // 9:18
          deviceStatus: 'online',
        ),
      ));

      expect(_text('9:18'), findsOneWidget);
      expect(_text('Next update in'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(_text('9:17'), findsOneWidget);

      await tester.pump(const Duration(seconds: 17));
      expect(_text('9:00'), findsOneWidget);

      await tester.pump(const Duration(seconds: 60));
      expect(_text('8:00'), findsOneWidget);

      // Tear down so the periodic ticker is disposed (a live timer at the end
      // of a test is reported as a leak).
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('reaches zero, shows Due now, and holds without a negative value', (tester) async {
    await withClock(tester.binding.clock, () async {
      await tester.pumpWidget(_wrap(
        const JKBMSRNextUpdateCountdown(
          secondsUntilNextExpectedCheckIn: 2,
          deviceStatus: 'online',
        ),
      ));

      expect(_text('0:02'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(_text('Due now'), findsOneWidget);

      // No ticker keeps running once due; the label stays honest rather than
      // counting negative.
      await tester.pump(const Duration(seconds: 5));
      expect(_text('Due now'), findsOneWidget);
      expect(_text('-'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('renders nothing when the interval is absent', (tester) async {
    await tester.pumpWidget(_wrap(
      const JKBMSRNextUpdateCountdown(
        secondsUntilNextExpectedCheckIn: null,
        deviceStatus: 'online',
      ),
    ));
    expect(_text('Next update'), findsNothing);
    expect(_text('Due now'), findsNothing);
  });

  testWidgets('renders nothing for an offline gateway even with a value', (tester) async {
    await tester.pumpWidget(_wrap(
      const JKBMSRNextUpdateCountdown(
        secondsUntilNextExpectedCheckIn: 300,
        deviceStatus: 'offline',
      ),
    ));
    expect(_text('Next update'), findsNothing);
    expect(_text('Due now'), findsNothing);
  });
}
