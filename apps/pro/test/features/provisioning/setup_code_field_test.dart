// The six-box code field: the cases that decide whether typing a code is
// pleasant or infuriating. Paste and backspace are the two people hit first.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jkbmsr_pro/features/provisioning/widgets/setup_code_field.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

void main() {
  Future<String> pump(WidgetTester tester, {required List<String> seen}) async {
    var code = '';
    await tester.pumpWidget(MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: Scaffold(
        body: SetupCodeField(onChanged: (value) {
          code = value;
          seen.add(value);
        }),
      ),
    ));
    await tester.pump();
    return code;
  }

  testWidgets('typing six digits fills all six boxes and emits the code',
      (tester) async {
    final seen = <String>[];
    await pump(tester, seen: seen);

    const digits = ['4', '1', '8', '3', '0', '2'];
    for (var i = 0; i < digits.length; i++) {
      await tester.enterText(find.byType(TextField).at(i), digits[i]);
      await tester.pump();
    }

    expect(seen.last, '418302');
  });

  testWidgets('a pasted code is distributed across the boxes', (tester) async {
    final seen = <String>[];
    await pump(tester, seen: seen);

    await tester.enterText(find.byType(TextField).first, '418302');
    await tester.pump();

    expect(seen.last, '418302');
    final values = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.controller!.text)
        .toList();
    expect(values, ['4', '1', '8', '3', '0', '2']);
  });

  testWidgets('the field reports exactly what is filled, never a padded guess',
      (tester) async {
    final seen = <String>[];
    await pump(tester, seen: seen);

    await tester.enterText(find.byType(TextField).first, '41');
    await tester.pump();

    expect(seen.last, '41');
  });
}
