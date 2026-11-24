// Switching ranges and failing used to leave the previously loaded 30-day
// points on screen under a highlighted 7d selector. A failed read must not
// present old data as if it covered the new range.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jkbmsr_pro/features/history/telemetry_history_screen.dart';
import 'package:jkbmsr_pro/services/api_client.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a failed range switch does not render the old range under the new selector',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    var historyCalls = 0;
    APIClient.configure(
      baseUrl: 'https://test.local',
      client: MockClient((request) async {
        if (request.url.path == '/v1/dashboard/devices/gw-1/telemetry/monthly-history') {
          historyCalls++;
          if (historyCalls == 1) {
            return _json({
              'available': true,
              'downsampled': false,
              'rows': [
                {
                  'timestamp': '2026-11-01T00:00:00Z',
                  'voltage': 52.1,
                  'current': 1.2,
                  'soc': 80.0,
                  'power': 62.5,
                  'temperature1': 24.0,
                  'temperature2': 23.0,
                },
                {
                  'timestamp': '2026-11-02T00:00:00Z',
                  'voltage': 52.3,
                  'current': 1.4,
                  'soc': 81.0,
                  'power': 73.2,
                  'temperature1': 24.5,
                  'temperature2': 23.5,
                },
              ],
            }, 200);
          }
          return _json({'error': 'upstream unavailable'}, 500);
        }
        return _json({'error': 'not found'}, 404);
      }),
    );

    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: const TelemetryHistoryScreen(deviceId: 'gw-1'),
    ));
    await tester.pumpAndSettle();

    // The 30-day load succeeded, so its charts are on screen.
    expect(find.text('Voltage (V)'), findsOneWidget);

    await tester.tap(find.text('7d'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load history'), findsOneWidget);
    expect(find.text('Voltage (V)'), findsNothing);
    expect(find.text('7d'), findsNothing);

    // Let the request-deduplication and snackbar timers expire before the tree
    // is disposed.
    await tester.pump(const Duration(seconds: 6));
  });
}
