// A failed sign-in history read is not an empty history. Before this test the
// Recent Sign-ins card said "No sign-in history recorded yet." for a 500.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jkbmsr_pro/features/settings/settings_screen.dart';
import 'package:jkbmsr_pro/services/api_client.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    const packageChannel = MethodChannel('dev.fluttercommunity.plus/package_info');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageChannel, (call) async {
      if (call.method == 'getAll') {
        return <String, dynamic>{
          'appName': 'JK BMS Remote',
          'packageName': 'com.jkbmsr.pro',
          'version': '1.3.55',
          'buildNumber': '87',
          'buildSignature': '',
        };
      }
      return null;
    });

    APIClient.configure(
      baseUrl: 'https://test.local',
      client: MockClient((request) async {
        final path = request.url.path;
        if (path == '/v1/dashboard/devices') {
          return _json({
            'devices': [
              {
                'id': 'gw-1',
                'name': 'Home Battery',
                'status': 'online',
                'targetHardware': 'esp32dev',
                'otaChannel': 'stable',
                'soc': 80,
                'voltage': 52.1,
                'current': 1.2,
                'firmwareVersion': '1.2.3',
                'lastSeen': '2026-10-09 10:00:00',
                'updateAvailable': false,
                'isOwner': true,
              }
            ],
          }, 200);
        }
        if (path == '/v1/dashboard/devices/gw-1/config') {
          return _json({'config': <String, dynamic>{}}, 200);
        }
        if (path == '/v1/user/sessions') {
          return _json({'error': 'internal error'}, 500);
        }
        return _json({'error': 'not found'}, 404);
      }),
    );
  });

  testWidgets('a failed sign-in history read does not read as an empty history',
      (tester) async {
    tester.view.physicalSize = const Size(400, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: SettingsScreen(externalLinkLauncher: (_) async => true),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();

    expect(find.text('No sign-in history recorded yet.'), findsNothing);
    expect(find.text('Sign-in history could not be loaded.'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Try again'), findsOneWidget);

    // Let the request-deduplication timers expire before the tree is disposed.
    await tester.pump(const Duration(seconds: 6));
  });
}
