import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_contributor/l10n/strings.dart';
import 'package:jkbmsr_contributor/models/consent.dart';
import 'package:jkbmsr_contributor/models/contribution.dart';
import 'package:jkbmsr_contributor/screens/review_screen.dart';

import '../support/fake_flutter_blue_plus.dart';
import '../support/jk02_fixtures.dart';

/// Mounts the review screen on a tall surface so every field, the summary and
/// the raw-JSON view are built without scrolling.
Future<void> _pumpReview(
  WidgetTester tester, {
  String? serial = '2021602096',
  ConsentRecord? consent,
}) async {
  tester.view.physicalSize = const Size(1200, 7000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: ReviewScreen(
        contribution: sampleContribution(),
        rawSerial: serial,
        consent: consent,
      ),
    ),
  );
}

/// The payload size shown in the summary, in bytes.
int _shownSize(WidgetTester tester) {
  final text = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data)
      .whereType<String>()
      .firstWhere((s) => s.endsWith(' bytes'), orElse: () => '');
  return int.parse(text.split(' ').first);
}

/// Expands "View raw JSON" and returns the exact document being reviewed.
Future<String> _openRawJson(WidgetTester tester) async {
  await tester.tap(find.text('View raw JSON'));
  await tester.pumpAndSettle();
  return tester.widget<SelectableText>(find.byType(SelectableText)).data!;
}

void main() {
  setUp(installFakeFlutterBluePlus);

  testWidgets('renders the real payload: values, counts and size',
      (WidgetTester tester) async {
    await _pumpReview(tester);

    // A real value from the captured fixture is shown beside its field.
    expect(find.textContaining('JK-B2A24S15P'), findsWidgets);
    expect(_shownSize(tester), greaterThan(0));
    // All sixteen opt-out fields start included.
    expect(find.text('16 of 16'), findsOneWidget);
    // Serial is withheld by default.
    expect(find.text('withheld'), findsOneWidget);
  });

  testWidgets('unchecking a field trims it from the payload',
      (WidgetTester tester) async {
    await _pumpReview(tester);
    final before = _shownSize(tester);

    expect(find.text('16 of 16'), findsOneWidget);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Model name'));
    await tester.pumpAndSettle();

    // The field is now omitted, and the omission is listed and recorded.
    expect(find.text('15 of 16'), findsOneWidget);
    expect(find.text(ReviewStrings.omittedTitle), findsOneWidget);
    expect(find.textContaining('•  Model name'), findsOneWidget);

    final json = await _openRawJson(tester);
    expect(json, isNot(contains('"modelName"')));
    expect(json, contains('"hardwareVersion"'));
    expect(json, contains('"omittedFields"'));

    // Removing a large section genuinely shrinks the payload.
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Telemetry samples'));
    await tester.pumpAndSettle();
    expect(_shownSize(tester), lessThan(before));
  });

  testWidgets('serial is off by default and only shared when switched on',
      (WidgetTester tester) async {
    await _pumpReview(tester);
    expect(find.text('withheld'), findsOneWidget);

    final serialTile =
        find.widgetWithText(SwitchListTile, ReviewStrings.serialLabel);
    expect(tester.widget<SwitchListTile>(serialTile).value, isFalse);

    await tester.tap(serialTile);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(serialTile).value, isTrue);
    expect(find.text('shared'), findsOneWidget);

    final json = await _openRawJson(tester);
    expect(json, contains('2021602096'));
    expect(json, contains('"shared"'));
  });

  testWidgets('a granted consent is stamped onto the payload',
      (WidgetTester tester) async {
    await _pumpReview(
      tester,
      consent: ConsentRecord(
        givenAt: DateTime.utc(2026, 10, 14, 9),
        scope: ConsentState.scope,
      ),
    );

    final json = await _openRawJson(tester);
    expect(json, contains('"consent"'));
    expect(json, contains(ConsentState.scope));
  });

  testWidgets('submit is a labelled seam, not a submit',
      (WidgetTester tester) async {
    await _pumpReview(tester);

    await tester.tap(find.widgetWithText(FilledButton, ReviewStrings.submit));
    await tester.pump();

    expect(find.text(ReviewStrings.submitSeam), findsOneWidget);
  });
}
