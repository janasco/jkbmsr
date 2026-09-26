// App-bar search: it must search actual gateways (not just repeat the bottom
// nav), open each gateway's dashboard, and still offer the quick-nav actions
// when the gateway fetch fails.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jkbmsr_pro/app/app.dart';
import 'package:jkbmsr_pro/services/api_client.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

http.Response _json(String body, int status) => http.Response(
      body,
      status,
      headers: {'content-type': 'application/json'},
    );

Widget _shell(String route, ValueChanged<String> onNavigate) => MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: JKBMSRShellLayout(
        currentRoute: route,
        onNavigate: onNavigate,
        child: const SizedBox.shrink(),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('search lists gateways and selecting one opens its dashboard',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    APIClient.configure(
      baseUrl: 'https://test.local',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/devices')) {
          return _json(
            jsonEncode({
              'devices': [
                {
                  'id': 'gw-1',
                  'name': 'Home Battery',
                  'status': 'online',
                  'targetHardware': 'esp32dev',
                  'otaChannel': 'stable',
                  'soc': 80,
                  'voltage': 52,
                  'current': 3,
                  'lastSeen': 'now',
                  'updateAvailable': false,
                },
              ],
            }),
            200,
          );
        }
        return _json('{"error":"not found"}', 404);
      }),
    );

    String? navigated;
    await tester.pumpWidget(
      _shell('/dashboard?deviceId=other', (route) => navigated = route),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home Battery · gw-1'), findsNothing);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    // Gateway row (from the live fetch) sits above the quick-nav fallback.
    expect(find.text('Home Battery · gw-1'), findsOneWidget);
    expect(find.text('Go to Dashboard'), findsOneWidget);

    await tester.tap(find.text('Home Battery · gw-1'));
    await tester.pumpAndSettle();

    expect(navigated, '/dashboard?deviceId=gw-1');

    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a failed gateway fetch still leaves the quick-nav actions',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    APIClient.configure(
      baseUrl: 'https://test.local',
      client: MockClient((request) async => _json('{"error":"boom"}', 500)),
    );

    String? navigated;
    await tester.pumpWidget(
      _shell('/dashboard?deviceId=other', (route) => navigated = route),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    // Never an empty palette: navigation actions remain selectable.
    expect(find.text('Go to Dashboard'), findsOneWidget);
    await tester.tap(find.text('Check Alerts'));
    await tester.pumpAndSettle();

    expect(navigated, '/alerts');

    await tester.pump(const Duration(seconds: 6));
  });
}
