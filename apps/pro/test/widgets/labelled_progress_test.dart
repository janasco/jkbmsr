import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';
import 'package:jkbmsr_pro/widgets/shared/labelled_progress.dart';

void main() {
  testWidgets('a wait always carries its label, in both layouts', (tester) async {
    for (final compact in [false, true]) {
      await tester.pumpWidget(MaterialApp(
        theme: JKBMSRTheme.darkTheme,
        home: Scaffold(body: Center(child: LabelledProgress(
          label: 'Reading the latest values',
          compact: compact,
        ))),
      ));
      await tester.pump();

      // A spinner with no label is indistinguishable from a stuck one.
      expect(find.text('Reading the latest values'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    }
  });
}
