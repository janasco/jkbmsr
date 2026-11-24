// An empty filter result is not an all-clear. Before this test, selecting
// "Critical" with only warnings present printed "No active alarms - All
// battery systems are operating within normal parameters."
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jkbmsr_pro/features/alerts/alerts_screen.dart';
import 'package:jkbmsr_pro/services/api_client.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/components.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _warning() => {
      'id': 'alert-1',
      'deviceId': 'gw-1',
      'deviceName': 'Garage pack',
      'severity': 'warning',
      'message': 'Cell 4 is drifting low',
      'createdAt': '2026-11-20 10:00:00',
      'isResolved': false,
    };

void main() {
  testWidgets('a filter with no matches is not an all-clear', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    APIClient.configure(
      baseUrl: 'https://test.local',
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/dashboard/alerts')) {
          return _json({
            'alerts': [_warning()],
            'hasMore': false,
          }, 200);
        }
        if (path.endsWith('/dashboard/devices')) {
          return _json({'devices': <dynamic>[]}, 200);
        }
        return _json({}, 200);
      }),
    );

    await tester.pumpWidget(MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: const AlertsScreen(),
    ));
    await tester.pumpAndSettle();

    // The warning is on screen, so the all-clear sentence is already wrong.
    expect(find.text('Cell 4 is drifting low'), findsOneWidget);

    await tester.tap(find.descendant(
      of: find.byType(JKBMSRSegmentedControl<String>),
      matching: find.text('Critical'),
    ));
    await tester.pumpAndSettle();

    expect(
      find.text('All battery systems are operating within normal parameters.'),
      findsNothing,
    );
    expect(find.text('No alarms match this search or filter'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Show all alarms'), findsOneWidget);

    // Let the request-deduplication timers expire before the tree is disposed.
    await tester.pump(const Duration(seconds: 6));
  });
}
