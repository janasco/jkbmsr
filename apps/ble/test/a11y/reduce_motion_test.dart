// Accessibility device pass: reduced-motion (OS "Remove animations") audit.
//
// Every looping primitive in lib/widgets/motion_kit.dart is supposed to consult
// `platformDispatcher.accessibilityFeatures.disableAnimations` before calling
// `AnimationController.repeat()`. PulseGlow did not in initState — only in
// didUpdateWidget — so a user who had asked the OS to disable animations still
// got the perpetual breathing glow. These tests are the executable substitute
// for a device pass (no Android emulator/KVM is available here).
//
// The positive control matters as much as the assertion: a test that only
// checks "no frames are scheduled" would pass if the widget rendered nothing at
// all. The second test proves the same widget DOES animate when the OS permits
// it, so the first test cannot be vacuous.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/widgets/motion_kit.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: Center(child: child)),
    );

void _setDisableAnimations(WidgetTester tester, bool value) {
  tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: value);
  addTearDown(tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

void main() {
  testWidgets('PulseGlow does not loop when the OS disables animations',
      (tester) async {
    _setDisableAnimations(tester, true);

    await tester.pumpWidget(_wrap(
      const PulseGlow(
        color: Color(0xFF10B981),
        child: SizedBox(width: 24, height: 24),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: 'PulseGlow kept scheduling frames with disableAnimations on — '
          'its repeat() is not gated on reduced motion.',
    );
  });

  testWidgets('positive control: PulseGlow DOES loop when animations are allowed',
      (tester) async {
    _setDisableAnimations(tester, false);

    await tester.pumpWidget(_wrap(
      const PulseGlow(
        color: Color(0xFF10B981),
        child: SizedBox(width: 24, height: 24),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      tester.binding.hasScheduledFrame,
      isTrue,
      reason: 'The control must animate, or the reduced-motion assertion above '
          'would pass for a widget that renders nothing.',
    );
  });
}
