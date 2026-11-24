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

  testWidgets('version states use purpose-built words, not alarm or link words',
      (tester) async {
    for (final entry in {
      JKBMSRStatus.updateAvailable: 'Update available',
      JKBMSRStatus.upToDate: 'Up to date',
      JKBMSRStatus.latest: 'Latest',
    }.entries) {
      await tester.pumpWidget(_wrap(JKBMSRStatusBadge(status: entry.key)));
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('Warning'), findsNothing);
      expect(find.text('Online'), findsNothing);
    }
  });

  testWidgets('version states expose a complete semantics label', (tester) async {
    await tester.pumpWidget(
      _wrap(const JKBMSRStatusBadge(status: JKBMSRStatus.updateAvailable)),
    );

    // "Update available status" would be the operational template applied to a
    // sentence that is already complete.
    expect(find.bySemanticsLabel('Update available'), findsOneWidget);
    expect(find.bySemanticsLabel('Update available status'), findsNothing);
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
