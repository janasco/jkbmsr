// History-tab deletion: per-alert delete and "Delete all history", both behind
// an explicit permanent-deletion confirmation. The alerts screen is
// offline-pumpable by injecting a mock http.Client into the APIClient singleton
// (same seam the search/back tests use).
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

Map<String, dynamic> _resolved(String id, String message) => {
      'id': id,
      'deviceId': 'gw-1',
      'deviceName': 'Home Battery',
      'severity': 'warning',
      'message': message,
      'createdAt': '2026-09-01 10:00',
      'isResolved': true,
      'resolvedAt': '2026-09-01 11:00',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> deleteCalls;
  late List<Map<String, dynamic>> resolved;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    deleteCalls = [];
    resolved = [
      _resolved('a1', 'Over-voltage a1'),
      _resolved('a2', 'Under-voltage a2'),
    ];
  });

  void stubApi() {
    APIClient.configure(
      baseUrl: 'https://test.local',
      client: MockClient((request) async {
        final path = request.url.path;

        // Must be checked before the generic /alerts/<id> branch below.
        if (request.method == 'DELETE' && path.endsWith('/alerts/resolved')) {
          final count = resolved.length;
          resolved = [];
          return _json({'ok': true, 'deletedCount': count}, 200);
        }
        if (request.method == 'DELETE' && path.contains('/alerts/')) {
          final id = request.url.pathSegments.last;
          deleteCalls.add(id);
          resolved = resolved.where((a) => a['id'] != id).toList();
          return _json({'ok': true, 'deleted': id}, 200);
        }
        if (path.endsWith('/alerts')) {
          final status = request.url.queryParameters['status'];
          if (status == 'resolved') {
            return _json({'alerts': resolved, 'hasMore': false}, 200);
          }
          return _json({'alerts': [], 'hasMore': false}, 200);
        }
        return _json({}, 200);
      }),
    );
  }

  Future<void> pumpHistory(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    stubApi();
    await tester.pumpWidget(MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: const AlertsScreen(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alert History'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'per-alert delete confirms permanently, calls DELETE, and refreshes',
      (tester) async {
    await pumpHistory(tester);

    expect(find.text('Over-voltage a1'), findsOneWidget);
    expect(find.text('Under-voltage a2'), findsOneWidget);

    // Two history rows each expose a Delete affordance.
    expect(find.text('Delete'), findsNWidgets(2));

    await tester.tap(find.text('Delete').first);
    await tester.pumpAndSettle();

    // Confirmation is explicit that this is permanent (unlike resolve).
    expect(find.text('Delete this alert permanently?'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(deleteCalls, ['a1']);
    expect(find.text('Over-voltage a1'), findsNothing);
    expect(find.text('Under-voltage a2'), findsOneWidget);
    expect(find.text('Alert deleted'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('Delete all history confirms and empties the list',
      (tester) async {
    await pumpHistory(tester);

    await tester.tap(find.text('Delete all history'));
    await tester.pumpAndSettle();

    expect(find.text('Delete all alert history?'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete all'));
    await tester.pumpAndSettle();

    expect(find.text('Over-voltage a1'), findsNothing);
    expect(find.text('Under-voltage a2'), findsNothing);
    expect(find.text('No resolved alerts yet'), findsOneWidget);
    expect(find.textContaining('Deleted 2 resolved alerts'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('active alarms still offer Resolve, not Delete', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    APIClient.configure(
      baseUrl: 'https://test.local',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/alerts')) {
          return _json({
            'alerts': [
              {
                'id': 'active-1',
                'deviceId': 'gw-1',
                'deviceName': 'Home Battery',
                'severity': 'critical',
                'message': 'Cell imbalance',
                'createdAt': '2026-09-01 09:00',
                'isResolved': false,
              },
            ],
            'hasMore': false,
          }, 200);
        }
        return _json({}, 200);
      }),
    );

    await tester.pumpWidget(MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: const AlertsScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Cell imbalance'), findsOneWidget);
    expect(find.text('Acknowledge'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);

    await tester.pump(const Duration(seconds: 6));
  });
}
