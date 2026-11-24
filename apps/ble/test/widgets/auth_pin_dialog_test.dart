import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/widgets/auth_pin_dialog.dart';

// The PIN dialog told every reader the factory PIN. Printing the fallback
// turns a write gate into a formality: anyone holding the phone could unlock
// controls without ever being told the PIN. The dialog still has to explain
// that this is a local PIN rather than an account, so the explanation stays
// and only the value goes.

Future<void> _openDialog(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AuthPinDialog(
                target: 'CONTROL',
                onVerifyPin: (_) async => true,
                onVerified: (_) {},
                onDismiss: () {},
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('never renders the default PIN', (tester) async {
    await _openDialog(tester);

    final visible = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toList();
    expect(visible, isNotEmpty);
    for (final text in visible) {
      expect(text, isNot(contains('1234')));
    }
  });

  testWidgets('still says this is a local PIN, not an account', (tester) async {
    await _openDialog(tester);

    expect(find.textContaining('Local control PIN, not an account'), findsOneWidget);
  });
}
