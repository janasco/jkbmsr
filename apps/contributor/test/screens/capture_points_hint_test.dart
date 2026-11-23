import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_contributor/screens/capture_screen.dart';
import 'package:jkbmsr_contributor/theme/app_theme.dart';

import '../support/fake_universal_ble.dart';

/// Points were earned and spendable and invisible. Zero of the captures donated
/// since the feature shipped carried a code, which is not a lack of interest: the
/// field is optional and sits after the work. The idle capture screen is the one
/// place a donor is already deciding whether to contribute.
void main() {
  setUp(installFakeUniversalBle);

  testWidgets('the capture screen asks for a code before the scan starts',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const CaptureScreen()),
    );
    await tester.pumpAndSettle();

    // The list builds lazily, so the hint only exists once it is scrolled to,
    // which is also how a user reaches it: it sits directly above the button.
    await tester.scrollUntilVisible(
      find.text('Have a code? Earn points'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Have a code? Earn points'), findsOneWidget);
    expect(find.textContaining('Points pay for cloud service days'), findsOneWidget);

    // The ask must not displace the action it exists to precede.
    final hint = tester.getTopLeft(find.text('Have a code? Earn points'));
    final scan = tester.getTopLeft(find.text('Scan for JK-BMS'));
    expect(hint.dy, lessThan(scan.dy));
  });
}
