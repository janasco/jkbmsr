// Wiring test: the Alerts screen's pack check card is fed from the gateway
// list and each gateway's latest telemetry, and degrades to the explicit
// no-data copy when there is nothing to read.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jkbmsr_pro/features/alerts/alerts_screen.dart';
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

Map<String, dynamic> _telemetry() => {
      'voltage': 53.2,
      'current': -12.0,
      'power': 638.4,
      'soc': 84,
      'temperature1': 22.0,
      'temperature2': 22.4,
      'cells': [
        {'cell': 1, 'voltage': 3.300},
        {'cell': 2, 'voltage': 3.355},
        {'cell': 3, 'voltage': 3.310},
        {'cell': 4, 'voltage': 3.300},
      ],
      'bms': {
        'fullCapacityAh': 100.0,
        'charging': false,
        'discharging': true,
      },
      'diagnostics': {'bmsLinkUp': true},
    };

Future<void> _pumpAlerts(
  WidgetTester tester, {
  required List<Map<String, dynamic>> devices,
}) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  APIClient.configure(
    baseUrl: 'https://test.local',
    client: MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/dashboard/alerts')) {
        return _json({'alerts': [], 'hasMore': false}, 200);
      }
      if (path.endsWith('/dashboard/devices')) {
        return _json({'devices': devices}, 200);
      }
      if (path.contains('/dashboard/devices/')) {
        return _json({'device': _device(), 'telemetry': _telemetry()}, 200);
      }
      return _json({}, 200);
    }),
  );

  await tester.pumpWidget(MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    home: const AlertsScreen(),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the card shows a finding derived from the latest telemetry',
      (tester) async {
    await _pumpAlerts(tester, devices: [_device()]);

    expect(find.text('Pack check'), findsOneWidget);
    expect(find.text('Cell 2 is 55 mV above cell 1'), findsOneWidget);
    expect(find.textContaining('spread 55 mV'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6)); // drain dedupe/toast timers
  });

  testWidgets('with no gateways the card says it cannot decide',
      (tester) async {
    await _pumpAlerts(tester, devices: const []);

    expect(find.text('Pack check'), findsOneWidget);
    expect(find.text('Not enough data to check the pack'), findsOneWidget);
    expect(
      find.text('No gateway telemetry is available to check.'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 6)); // drain dedupe/toast timers
  });
}
