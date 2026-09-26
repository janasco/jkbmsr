// Accessibility device pass: the alerts screen must not overflow at large OS
// text scales on a narrow phone.
//
// This guards a real bug: the alert card's "Gateway: …" and "ID: #… / <time>"
// rows had no Expanded/Flexible, so a long gateway name (or a long timestamp)
// overflowed at ~360dp with textScale 2.0. The screen is offline-pumpable by
// injecting a mock http.Client into the APIClient singleton.
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

// Worst-case real-world content: a long gateway name plus a long message.
const _longName = 'Warehouse Backup Bank — North Wing Array';
const _longMessage =
    'Cell 14 voltage dropped below the configured minimum threshold for more than three consecutive samples';

Map<String, dynamic> _alert(String id, {required bool resolved}) => {
      'id': id,
      'deviceId': 'gw-1',
      'deviceName': _longName,
      'severity': 'critical',
      'message': _longMessage,
      'createdAt': '2026-09-01 10:00:00',
      'isResolved': resolved,
      'resolvedAt': resolved ? '2026-09-01 11:00:00' : null,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void stubApi() {
    APIClient.configure(
      baseUrl: 'https://test.local',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/alerts')) {
          final resolved = request.url.queryParameters['status'] == 'resolved';
          return _json(
            {
              'alerts': [_alert('a1', resolved: resolved)],
              'hasMore': false,
            },
            200,
          );
        }
        return _json({}, 200);
      }),
    );
  }

  Future<void> pumpAlerts(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    stubApi();

    await tester.pumpWidget(MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2.0),
          ),
          child: const AlertsScreen(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('active alerts do not overflow at textScale 2.0 on a 360dp phone',
      (tester) async {
    await pumpAlerts(tester);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 6)); // drain toast timers
  });

  testWidgets('resolved alert history does not overflow at textScale 2.0',
      (tester) async {
    await pumpAlerts(tester);
    await tester.tap(find.text('Alert History'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 6)); // drain toast timers
  });
}
