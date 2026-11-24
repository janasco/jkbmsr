// A flash-log row is status plus timestamp. Before this test the row was a
// spaceBetween Row with two unconstrained Texts, so at 2x text on a narrow
// phone it overflowed and clipped; the timestamp also printed the API's naive
// UTC string verbatim while every other screen converted it to local time.
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
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a flash log row does not overflow at 2x text and shows local time',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    APIClient.configure(
      baseUrl: 'https://test.local',
      client: MockClient((request) async {
        final path = request.url.path;
        if (path == '/v1/dashboard/devices/gw-1/config') {
          return _json({
            'config': {
              'firmwareVersion': '0.9.24',
              'latestFirmwareVersion': '0.9.24',
              'updateAvailable': false,
            },
          }, 200);
        }
        if (path == '/v1/dashboard/devices/gw-1/ota/history') {
          return _json({
            'events': [
              {
                'id': 1,
                'lastResult': 'success',
                'offeredVersion': '0.9.24',
                'lastCheckSucceeded': true,
                'updateAvailable': false,
                'updateApplied': true,
                'createdAt': '2026-09-01 10:00:00',
              },
            ],
          }, 200);
        }
        return _json({'error': 'not found'}, 404);
      }),
    );

    await tester.pumpWidget(MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2.0),
          ),
          child: const OTAScreen(deviceId: 'gw-1'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Bring the log row into view so its layout is actually exercised; an
    // off-screen child would make the overflow assertion vacuous.
    await tester.scrollUntilVisible(
      find.textContaining('Status: success'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // The raw string is UTC as sent and carries seconds; the row must show the
    // converted local form instead.
    expect(find.text('2026-09-01 10:00:00'), findsNothing);
    final localTime = RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$');
    final renderedTimes = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>()
        .where(localTime.hasMatch)
        .toList();
    expect(renderedTimes, isNotEmpty,
        reason: 'the flash log should render a local YYYY-MM-DD HH:MM timestamp');

    // The config/history loads keep a request-deduplication timer alive for a
    // few seconds; let it expire before the tree is disposed.
    await tester.pump(const Duration(seconds: 6));
  });
}
