// The Tools hub: three verbs, and the two that can open without data do open.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jkbmsr_pro/features/tools/tools_screen.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

Widget _host(Widget child) => MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: inner!,
      ),
      home: child,
    );

void main() {
  testWidgets('the hub offers exactly the three things it exists for',
      (tester) async {
    await tester.pumpWidget(_host(const ToolsScreen()));
    await tester.pump();

    expect(find.text('Diagnose'), findsOneWidget);
    expect(find.text('Guide'), findsOneWidget);
    expect(find.text('Add a gateway'), findsOneWidget);
  });

  testWidgets('the guide opens', (tester) async {
    await tester.pumpWidget(_host(const ToolsScreen()));
    await tester.pump();

    await tester.tap(find.text('Guide'));
    await tester.pumpAndSettle();

    expect(
      find.text('Short answers to the questions a reading raises.'),
      findsOneWidget,
    );
  });

  testWidgets('add a gateway opens the scan screen, which says when the radio is absent',
      (tester) async {
    await tester.pumpWidget(_host(const ToolsScreen()));
    await tester.pump();

    await tester.tap(find.text('Add a gateway'));
    await tester.pump();
    await tester.pump();

    // The scan screen is honest about a build without the BLE stack rather than
    // showing an empty room.
    expect(find.text('Bluetooth setup is not ready'), findsOneWidget);
  });
}
