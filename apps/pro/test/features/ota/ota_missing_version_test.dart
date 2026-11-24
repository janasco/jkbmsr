// A missing version is unknown, not 0.1.2. Before this test the OTA screen
// defaulted both versions to "0.1.2" and a successful check claimed the
// gateway was up to date even when the server reported no latest version.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jkbmsr_pro/features/ota/ota_screen.dart';
import 'package:jkbmsr_pro/services/api_client.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  testWidgets('a config without versions shows "-" and never claims up to date',
      (tester) async {
    tester.view.physicalSize = const Size(500, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    APIClient.configure(
      baseUrl: 'https://test.local',
      client: MockClient((request) async {
        final path = request.url.path;
        if (path == '/v1/dashboard/devices/gw-1/config') {
          return _json({'config': <String, dynamic>{}}, 200);
        }
        if (path == '/v1/dashboard/devices/gw-1/ota/history') {
          return _json({'events': <dynamic>[]}, 200);
        }
        if (path == '/v1/dashboard/devices/gw-1/ota/check') {
          return _json({'ok': true}, 200);
        }
        return _json({'error': 'not found'}, 404);
      }),
    );

    await tester.pumpWidget(MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: const OTAScreen(deviceId: 'gw-1'),
    ));
    await tester.pumpAndSettle();

    // Current Version and Latest Server Version, both unknown.
    expect(find.text('-'), findsNWidgets(2));
    expect(find.text('0.1.2'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Check Update'));
    await tester.pumpAndSettle();

    expect(find.text('Gateway is currently up to date'), findsNothing);
    expect(
      find.text('The server did not report a latest firmware version'),
      findsOneWidget,
    );

    // Let the deduplication TTL timers expire before the tree is disposed.
    await tester.pump(const Duration(seconds: 6));
  });
}
