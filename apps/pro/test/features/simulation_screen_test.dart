import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/features/simulation/simulation_screen.dart';
import 'package:jkbmsr_pro/models/simulation_claim.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

Widget _app(Widget child) => MaterialApp(theme: JKBMSRTheme.darkTheme, home: child);

/// Tall enough that the whole screen builds: the reward card sits below the fold
/// on a phone, and a lazily built ListView would make its button invisible to the
/// test rather than absent from the app.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  test('a claim carries the credited amount, the reason and the account balance', () {
    final credited = SimulationClaimResult.fromJson(
        {'credited': 10, 'reason': null, 'balance': 120});
    expect(credited.credited, 10);
    expect(credited.reason, isNull);
    expect(credited.balance, 120);

    final refused = SimulationClaimResult.fromJson(
        {'credited': 0, 'reason': 'already claimed today', 'balance': 120});
    expect(refused.credited, 0);
    expect(refused.reason, 'already claimed today');
  });

  testWidgets('the screen says it is made up before it shows any number', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(const SimulationScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Simulation. These numbers are made up'), findsOneWidget);
    expect(find.textContaining('10 points a day'), findsOneWidget);
  });

  testWidgets('the claim stays shut until a session has run a minute', (tester) async {
    _tall(tester);
    var calls = 0;
    await tester.pumpWidget(_app(SimulationScreen(
      claimReward: (seconds) async {
        calls += 1;
        expect(seconds, greaterThanOrEqualTo(60));
        return const SimulationClaimResult(credited: 10, reason: null, balance: 10);
      },
    )));
    await tester.pumpAndSettle();

    final claim = find.widgetWithText(FilledButton, 'Claim 10 points');
    expect(tester.widget<FilledButton>(claim).onPressed, isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Run'));
    await tester.pump(const Duration(seconds: 61));
    await tester.pump();

    expect(tester.widget<FilledButton>(claim).onPressed, isNotNull);
    await tester.tap(claim);
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.textContaining('10 points added'), findsOneWidget);
  });

  testWidgets('a refused claim explains the rule that refused it', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(SimulationScreen(
      claimReward: (seconds) async =>
          const SimulationClaimResult(credited: 0, reason: 'no gateway', balance: 0),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Run'));
    await tester.pump(const Duration(seconds: 61));
    await tester.tap(find.widgetWithText(FilledButton, 'Claim 10 points'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Claim a gateway on this account first'), findsOneWidget);
  });

  testWidgets('a weak cell lowers one cell and widens the spread', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(const SimulationScreen()));
    await tester.pumpAndSettle();

    final before = tester.widget<Text>(
      find.textContaining('spread').first,
    );
    await tester.tap(find.text('Weaken a cell'));
    await tester.pumpAndSettle();
    final after = tester.widget<Text>(find.textContaining('spread').first);

    expect(before.data, isNot(equals(after.data)));
    expect(after.data, contains('220 mV'));
  });

  testWidgets('a dropped link freezes the readings, as a real gateway looks', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(const SimulationScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Run'));
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.text('Drop the link'));
    await tester.pump();

    expect(find.text('down'), findsOneWidget);

    String voltage() => tester
        .widgetList<Text>(find.textContaining(' V'))
        .map((text) => text.data ?? '')
        .first;
    final frozen = voltage();
    await tester.pump(const Duration(seconds: 10));
    expect(voltage(), frozen);
  });
}
