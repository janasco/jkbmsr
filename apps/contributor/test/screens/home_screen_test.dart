import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jkbmsr_contributor/screens/capture_screen.dart';
import 'package:jkbmsr_contributor/screens/home_screen.dart';
import 'package:jkbmsr_contributor/services/coverage_service.dart';
import 'package:jkbmsr_contributor/theme/app_theme.dart';

import '../support/fake_flutter_blue_plus.dart';

/// The aggregate-only summary, as the endpoint returns it. Only the two counts
/// the screen displays are asserted; the rest exists so the parser is fed a
/// realistic document rather than a hand-shrunk one.
const Map<String, Object> _summary = {
  'contributions': 12,
  'models': 9,
  'hardwareRevisions': 6,
  'firmwareRevisions': 8,
  'minCells': 8,
  'maxCells': 23,
  'minSamples': 7,
  'maxSamples': 76,
  'lastUpdated': '2026-11-09T12:30:34.923Z',
};

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: child,
    );

CoverageService _respondingWith(int status, String body) => CoverageService(
      client: MockClient((_) async => http.Response(body, status)),
    );

void main() {
  setUp(installFakeFlutterBluePlus);

  testWidgets('a successful fetch renders the live corpus counts',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        HomeScreen(
          coverageService: _respondingWith(200, jsonEncode(_summary)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('12 packs contributed · 9 models so far'),
      findsOneWidget,
    );

    // The line is additional, not a replacement: the screen is otherwise the
    // same one it was before the fetch.
    expect(find.text('Start a capture'), findsOneWidget);
  });

  testWidgets('a failed fetch renders nothing and does not throw',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        HomeScreen(
          coverageService: CoverageService(
            client: MockClient(
              (_) async => throw http.ClientException('offline'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('contributed'), findsNothing);
    expect(find.textContaining('models so far'), findsNothing);
    expect(tester.takeException(), isNull);

    // An unreachable API leaves the capture flow exactly as it was.
    expect(find.text('Start a capture'), findsOneWidget);
  });

  testWidgets('the capture action is tappable while the fetch is in flight',
      (WidgetTester tester) async {
    final pending = Completer<http.Response>();

    await tester.pumpWidget(
      _host(
        HomeScreen(
          coverageService: CoverageService(
            client: MockClient((_) => pending.future),
          ),
        ),
      ),
    );

    // The first frame is the whole screen: no spinner, no disabled button.
    final button = find.widgetWithText(FilledButton, 'Start a capture');
    expect(button, findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(CaptureScreen), findsOneWidget);

    // Complete the request so nothing is left pending when the test ends.
    pending.complete(http.Response(jsonEncode(_summary), 200));
    await tester.pumpAndSettle();
  });
}
