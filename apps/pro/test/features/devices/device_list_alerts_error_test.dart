// A failed alerts read is not an empty alerts list. Before this test the
// device list rendered "No alerts recorded yet." and an Active Alerts tile of
// 0 for a 500, which reads as an all-clear the app never observed.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jkbmsr_pro/features/devices/device_list_screen.dart';
import 'package:jkbmsr_pro/services/api_client.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _device() => {
      'id': 'gw-1',
      'name': 'Garage pack',
      'status': 'online',
      'targetHardware': 'esp32-s3-16mb',
      'otaChannel': 'stable',
      'soc': 84,
      'voltage': 53.2,
      'current': -12.0,
      'lastSeen': '2026-11-09 10:00:00',
      'updateAvailable': false,
      'expectedIntervalSeconds': 60,
      'secondsSinceLastTelemetry': 12,
      'isOwner': true,
    };

void main() {
  testWidgets('a failed alerts read says so instead of claiming there are none',
      (tester) async {
    tester.view.physicalSize = const Size(500, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    APIClient.configure(
      baseUrl: 'https://test.local',
      client: MockClient((request) async {
        final path = request.url.path;
        if (path == '/v1/dashboard/alerts') {
          return _json({'error': 'internal error'}, 500);
        }
        if (path == '/v1/dashboard/devices') {
          return _json({'devices': [_device()]}, 200);
        }
        if (path == '/v1/dashboard/devices/gw-1/telemetry/history') {
          return _json({'points': <dynamic>[]}, 200);
        }
        if (path == '/v1/dashboard/devices/gw-1/config') {
          return _json({'config': <String, dynamic>{}}, 200);
        }
        return _json({'error': 'not found'}, 404);
      }),
    );

    await tester.pumpWidget(MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: const DeviceListScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No alerts recorded yet.'), findsNothing);
    expect(find.text('No alerts in this period.'), findsNothing);
    // One line where Recent Alerts would be, one in the Alert Summary card.
    expect(
      find.text('Alerts could not be loaded. Pull to refresh.'),
      findsNWidgets(2),
    );
    // The Active Alerts tile must not read 0 when the count is unknown.
    expect(find.text('-'), findsOneWidget);

    // Let the request-deduplication timers expire before the tree is disposed.
    await tester.pump(const Duration(seconds: 6));
  });
}
