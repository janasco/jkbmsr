import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_contributor/l10n/strings.dart';
import 'package:jkbmsr_contributor/screens/capture_screen.dart';
import 'package:jkbmsr_contributor/screens/capture_success_screen.dart';
import 'package:jkbmsr_contributor/screens/consent_screen.dart';
import 'package:jkbmsr_contributor/services/capture_service.dart';
import 'package:jkbmsr_contributor/services/consent_controller.dart';
import 'package:jkbmsr_contributor/services/consent_store.dart';
import 'package:jkbmsr_contributor/theme/app_theme.dart';

import '../support/fake_flutter_blue_plus.dart';
import '../support/jk02_fixtures.dart';

/// There is no Android emulator on this host, so large-text behaviour is checked
/// by walking the real widget tree at 2× text on a real phone frame. Text that
/// overflows here is text a user who needs large type cannot read.
void main() {
  setUp(installFakeFlutterBluePlus);

  Future<void> mountAt2x(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: child,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the capture screen holds up at 2x text',
      (WidgetTester tester) async {
    await mountAt2x(tester, const CaptureScreen());

    expect(find.text('Capture your JK-BMS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the consent screen holds up at 2x text',
      (WidgetTester tester) async {
    await mountAt2x(
      tester,
      ConsentScreen(
          controller: ConsentController(store: InMemoryConsentStore())),
    );

    expect(find.text(ConsentStrings.title), findsOneWidget);
    // The decision is pinned, so it must still be reachable at large text.
    expect(find.text(ConsentStrings.accept), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the success screen holds up at 2x text',
      (WidgetTester tester) async {
    await mountAt2x(
      tester,
      CaptureSuccessScreen(
        outcome:
            CaptureOutcome.success(sampleContribution(), Jk02CaptureSession()),
      ),
    );

    expect(find.text('Contribution ready'), findsOneWidget);
    // The primary action is pinned below the content, so it must be reachable
    // without scrolling even when the text is large.
    expect(find.text('Review & contribute'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
