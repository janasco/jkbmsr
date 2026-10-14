import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_contributor/l10n/strings.dart';
import 'package:jkbmsr_contributor/main.dart';
import 'package:jkbmsr_contributor/models/consent.dart';
import 'package:jkbmsr_contributor/screens/capture_screen.dart';
import 'package:jkbmsr_contributor/screens/consent_screen.dart';
import 'package:jkbmsr_contributor/screens/home_screen.dart';
import 'package:jkbmsr_contributor/services/consent_controller.dart';
import 'package:jkbmsr_contributor/services/consent_store.dart';

import '../support/fake_flutter_blue_plus.dart';

Future<ConsentController> _pumpConsentScreen(WidgetTester tester) async {
  // A tall surface so the whole consent list is built without scrolling.
  tester.view.physicalSize = const Size(1200, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final controller = ConsentController(store: InMemoryConsentStore());
  await tester.pumpWidget(
    MaterialApp(home: ConsentScreen(controller: controller)),
  );
  return controller;
}

/// Gives the gate tests a tall surface so the consent overlay is fully built.
void _tallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(installFakeFlutterBluePlus);

  group('ConsentScreen', () {
    testWidgets('the opt-in is off and accept is disabled until turned on',
        (WidgetTester tester) async {
      await _pumpConsentScreen(tester);

      final accept = find.widgetWithText(FilledButton, ConsentStrings.accept);
      expect(accept, findsOneWidget);
      expect(tester.widget<FilledButton>(accept).onPressed, isNull);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
    });

    testWidgets('turning the opt-in on enables accept, which is persisted',
        (WidgetTester tester) async {
      final controller = await _pumpConsentScreen(tester);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      final accept = find.widgetWithText(FilledButton, ConsentStrings.accept);
      expect(tester.widget<FilledButton>(accept).onPressed, isNotNull);

      await tester.tap(accept);
      await tester.pumpAndSettle();

      expect(controller.isGranted, isTrue);
      expect(controller.state!.decidedAt, isNotNull);
    });

    testWidgets('"Not now" records a decline', (WidgetTester tester) async {
      final controller = await _pumpConsentScreen(tester);

      await tester.tap(find.text(ConsentStrings.decline));
      await tester.pumpAndSettle();

      expect(controller.hasDecision, isTrue);
      expect(controller.isGranted, isFalse);
    });
  });

  group('ConsentGate', () {
    testWidgets('blocks the app until consent is answered',
        (WidgetTester tester) async {
      _tallSurface(tester);
      final controller = ConsentController(store: InMemoryConsentStore());
      await controller.load();
      await tester.pumpWidget(ContributorApp(consent: controller));

      // Shown until answered.
      expect(find.text(ConsentStrings.title), findsOneWidget);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      await tester.tap(find.text(ConsentStrings.accept));
      await tester.pumpAndSettle();

      expect(controller.isGranted, isTrue);
      expect(find.text(ConsentStrings.title), findsNothing);
      expect(find.text('Start a capture'), findsOneWidget);
    });

    testWidgets('after a decline, capture asks again instead of scanning',
        (WidgetTester tester) async {
      _tallSurface(tester);
      final controller = ConsentController(store: InMemoryConsentStore());
      await controller.load();
      await tester.pumpWidget(ContributorApp(consent: controller));

      await tester.tap(find.text(ConsentStrings.decline));
      await tester.pumpAndSettle();
      expect(find.text(ConsentStrings.title), findsNothing);

      await tester.tap(find.text('Start a capture'));
      await tester.pumpAndSettle();

      // Re-asked, and never reached the capture screen.
      expect(find.text(ConsentStrings.title), findsOneWidget);
      expect(find.byType(CaptureScreen), findsNothing);
    });

    testWidgets('a stored grant goes straight to the shell',
        (WidgetTester tester) async {
      final controller = ConsentController(store: InMemoryConsentStore());
      await controller.decide(ConsentDecision.granted);

      await tester.pumpWidget(ContributorApp(consent: controller));

      expect(find.text(ConsentStrings.title), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });
}
