import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/features/onboarding/onboarding_screen.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Onboarding is the first screen a new owner sees, so it is the one that must
/// survive a large text scale — and the redesign moved it from a centred column
/// to a composed hero plus a scrollable block, which is exactly the kind of change
/// that can overflow.
void main() {
  testWidgets('onboarding survives 2x text with Next reachable', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: JKBMSRTheme.lightTheme,
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: OnboardingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your pack, from anywhere'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the step counter advances with the page', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: JKBMSRTheme.lightTheme, home: const OnboardingScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('STEP 1 OF 5'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.textContaining('STEP 2 OF 5'), findsOneWidget);
    expect(find.text('Every gateway in one place'), findsOneWidget);
  });
}
