import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/components.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.dark}) {
  return MaterialApp(
    theme: brightness == Brightness.dark ? JKBMSRTheme.darkTheme : JKBMSRTheme.lightTheme,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('shows the label text for each status', (tester) async {
    for (final entry in {
      JKBMSRStatus.online: 'Online',
      JKBMSRStatus.offline: 'Offline',
      JKBMSRStatus.warning: 'Warning',
      JKBMSRStatus.critical: 'Critical',
    }.entries) {
      await tester.pumpWidget(_wrap(JKBMSRStatusBadge(status: entry.key)));
      expect(find.text(entry.value), findsOneWidget);
    }
  });

  testWidgets('exposes a single merged semantics label for screen readers', (tester) async {
    await tester.pumpWidget(_wrap(const JKBMSRStatusBadge(status: JKBMSRStatus.critical)));

    expect(find.bySemanticsLabel('Critical status'), findsOneWidget);
  });

  testWidgets('renders in both light and dark themes without error', (tester) async {
    await tester.pumpWidget(
      _wrap(const JKBMSRStatusBadge(status: JKBMSRStatus.online), brightness: Brightness.light),
    );
    expect(find.text('Online'), findsOneWidget);

    await tester.pumpWidget(
      _wrap(const JKBMSRStatusBadge(status: JKBMSRStatus.online), brightness: Brightness.dark),
    );
    expect(find.text('Online'), findsOneWidget);
  });
}
