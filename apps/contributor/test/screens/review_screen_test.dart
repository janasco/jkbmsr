import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jkbmsr_contributor/l10n/strings.dart';
import 'package:jkbmsr_contributor/models/consent.dart';
import 'package:jkbmsr_contributor/models/contribution.dart';
import 'package:jkbmsr_contributor/models/contribution_selection.dart';
import 'package:jkbmsr_contributor/screens/review_screen.dart';
import 'package:jkbmsr_contributor/services/contribution_export.dart';
import 'package:jkbmsr_contributor/services/contribution_uploader.dart';

import '../support/fake_flutter_blue_plus.dart';
import '../support/jk02_fixtures.dart';

/// Mounts the review screen on a tall surface so every field, the summary and
/// the raw-JSON view are built without scrolling.
Future<void> _pumpReview(
  WidgetTester tester, {
  String? serial = '2021602096',
  ConsentRecord? consent,
  ContributionUploader? uploader,
  ContributionExporter? exporter,
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
        uploader: uploader,
        exporter: exporter,
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

  testWidgets('a successful submit shows the returned receipt id',
      (WidgetTester tester) async {
    http.Request? sent;
    final uploader = ContributionUploader(
      client: MockClient((request) async {
        sent = request;
        return http.Response(
          '{"id":"c_01926f6a-9a00-7000-8000-00000000abcd",'
          '"receivedAt":"2026-10-14T09:20:00.000Z"}',
          201,
        );
      }),
    );

    await _pumpReview(tester, uploader: uploader);
    await tester.tap(find.widgetWithText(FilledButton, ReviewStrings.submit));
    await tester.pumpAndSettle();

    expect(find.text(SubmitStrings.successTitle), findsOneWidget);
    expect(find.text('c_01926f6a-9a00-7000-8000-00000000abcd'), findsOneWidget);
    // The body posted is the exact document the screen displayed.
    final expected = sampleContribution()
        .withSerial('2021602096', include: false)
        .encode(selection: ContributionSelection.defaults());
    expect(sent?.body, expected);
    // No account: the request is anonymous.
    expect(sent?.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')));
  });

  testWidgets('a failed submit shows the honest reason and offers export',
      (WidgetTester tester) async {
    final uploader = ContributionUploader(
      client: MockClient((_) async => http.Response('{"error":"boom"}', 500)),
    );

    await _pumpReview(tester, uploader: uploader);
    await tester.tap(find.widgetWithText(FilledButton, ReviewStrings.submit));
    await tester.pumpAndSettle();

    expect(
      find.text(SubmitStrings.failureMessage(
        const SubmitFailure(kind: SubmitFailureKind.server),
      )),
      findsOneWidget,
    );
    // The mandatory fallback is offered, not buried.
    expect(
      find.widgetWithText(OutlinedButton, SubmitStrings.exportButton),
      findsOneWidget,
    );
  });

  testWidgets('a 429 is surfaced with its Retry-After, not retried',
      (WidgetTester tester) async {
    var calls = 0;
    final uploader = ContributionUploader(
      client: MockClient((_) async {
        calls++;
        return http.Response('{"error":"slow down"}', 429,
            headers: {'retry-after': '90'});
      }),
    );

    await _pumpReview(tester, uploader: uploader);
    await tester.tap(find.widgetWithText(FilledButton, ReviewStrings.submit));
    await tester.pumpAndSettle();

    // 90 seconds is reported as a rounded-up whole minute, never "90 seconds"
    // or "0 minutes".
    expect(find.textContaining('2 minutes'), findsOneWidget);
    expect(calls, 1, reason: 'the client must never auto-retry into a limit');
  });

  testWidgets('the export path hands over exactly the bytes submit would send',
      (WidgetTester tester) async {
    // The exporter's real byte-write is covered by contribution_export_test;
    // here the recording double proves the screen passes the *same* document
    // to both paths.
    final recorder = _RecordingExporter();
    http.Request? sent;
    final uploader = ContributionUploader(
      client: MockClient((request) async {
        sent = request;
        return http.Response('{"id":"c_ok"}', 201);
      }),
    );

    await _pumpReview(tester, uploader: uploader, exporter: recorder);

    await tester.tap(
      find.widgetWithText(OutlinedButton, SubmitStrings.exportButton),
    );
    await tester.pumpAndSettle();
    expect(recorder.exported, hasLength(1));
    expect(find.text(SubmitStrings.exportSuccessTitle), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, ReviewStrings.submit));
    await tester.pumpAndSettle();

    // Same bytes: the exported file is the document that was posted.
    expect(sent, isNotNull);
    expect(recorder.exported.single, sent!.body);
  });

  testWidgets('export is always available, even before any submit',
      (WidgetTester tester) async {
    await _pumpReview(tester, exporter: _RecordingExporter());

    expect(
      find.widgetWithText(OutlinedButton, SubmitStrings.exportButton),
      findsOneWidget,
    );
  });
}

/// A [ContributionExporter] that records the payload instead of touching the
/// filesystem, so the widget test does not need real async I/O (which does not
/// complete under `testWidgets`).
class _RecordingExporter extends ContributionExporter {
  _RecordingExporter() : super(documentsDirectory: () async => Directory.systemTemp);

  final List<String> exported = [];

  @override
  Future<File> exportAndShare(
    String payload, {
    required String contributionId,
    DateTime? capturedAt,
  }) async {
    exported.add(payload);
    return File('${Directory.systemTemp.path}/unused.json');
  }
}
