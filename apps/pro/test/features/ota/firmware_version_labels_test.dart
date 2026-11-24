// Version state is not alarm state and not connectivity state. The firmware
// card used to show a red-amber "Warning" purely because an update existed,
// and "Online" when it was current; the releases list marked the newest build
// "Online" too. A routine update read as a fault and a version read as a link.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jkbmsr_pro/features/ota/firmware_releases_screen.dart';
import 'package:jkbmsr_pro/features/settings/settings_screen.dart';
import 'package:jkbmsr_pro/services/api_client.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void _stubPlugins() {
  SharedPreferences.setMockInitialValues({});
  const packageChannel = MethodChannel('dev.fluttercommunity.plus/package_info');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(packageChannel, (call) async {
    if (call.method == 'getAll') {
      return <String, dynamic>{
        'appName': 'JK BMS Remote',
        'packageName': 'com.jkbmsr.pro',
        'version': '1.3.57',
        'buildNumber': '89',
        'buildSignature': '',
      };
    }
    return null;
  });
}

void _stubSettingsApi({required bool updateAvailable}) {
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
              'firmwareVersion': updateAvailable ? '0.9.13' : '0.9.24',
              'lastSeen': '2026-11-24 10:00:00',
              'updateAvailable': updateAvailable,
              'isOwner': true,
            }
          ],
        }, 200);
      }
      if (path == '/v1/dashboard/devices/gw-1/config') {
        return _json({
          'config': {
            'firmwareVersion': updateAvailable ? '0.9.13' : '0.9.24',
            'latestFirmwareVersion': '0.9.24',
            'updateAvailable': updateAvailable,
          },
        }, 200);
      }
      if (path == '/v1/dashboard/devices/gw-1/shares') {
        return _json({'shares': [], 'maxShares': 5}, 200);
      }
      if (path == '/v1/dashboard/devices/gw-1/wifi') {
        return _json({
          'wifi': {
            'currentSsid': 'HomeNet',
            'networks': [],
            'changeStatus': 'idle',
            'changeMessage': '',
          },
        }, 200);
      }
      if (path == '/v1/dashboard/devices/gw-1/wifi/target') {
        return _json({
          'target': null,
          'reported': null,
          'alert': {'active': false, 'lastSentAt': null, 'count': 0},
        }, 200);
      }
      if (path == '/v1/user/sessions') {
        return _json({'logins': []}, 200);
      }
      return _json({'error': 'not found'}, 404);
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpFirmwareCard(
    WidgetTester tester, {
    required bool updateAvailable,
  }) async {
    _stubPlugins();
    _stubSettingsApi(updateAvailable: updateAvailable);

    tester.view.physicalSize = const Size(400, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: const SettingsScreen(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Firmware & OTA'));
    await tester.pumpAndSettle();
  }

  Future<void> drainTimers(WidgetTester tester) async {
    // The config load keeps a request-deduplication timer alive for a few
    // seconds; let it expire before the tree is disposed.
    await tester.pump(const Duration(seconds: 6));
  }

  testWidgets('the firmware card says Update available, not Warning',
      (tester) async {
    await pumpFirmwareCard(tester, updateAvailable: true);

    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Warning'), findsNothing);
    expect(find.text('Online'), findsNothing);

    await drainTimers(tester);
  });

  testWidgets('the firmware card says Up to date, not Online', (tester) async {
    await pumpFirmwareCard(tester, updateAvailable: false);

    expect(find.text('Up to date'), findsOneWidget);
    expect(find.text('Warning'), findsNothing);
    expect(find.text('Online'), findsNothing);

    await drainTimers(tester);
  });

  testWidgets('the newest release is labelled Latest, not Online',
      (tester) async {
    _stubPlugins();
    APIClient.configure(
      baseUrl: 'https://test.local',
      client: MockClient((request) async {
        if (request.url.path == '/v1/dashboard/firmware/releases') {
          return _json({
            'releases': [
              {
                'id': 1,
                'version': '0.9.24',
                'targetHardware': 'esp32-s3-16mb',
                'rolloutChannel': 'stable',
                'releasedAt': '2026-11-20 09:00:00',
                'isLatest': true,
                'publicMirrorStatus': 'verified',
                'publicMirrorDetail': 'Artifact matches the published checksum.',
              },
            ],
          }, 200);
        }
        return _json({'error': 'not found'}, 404);
      }),
    );

    tester.view.physicalSize = const Size(500, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: const FirmwareReleasesScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Latest'), findsOneWidget);
    expect(find.text('Online'), findsNothing);
    expect(find.text('Warning'), findsNothing);

    await drainTimers(tester);
  });
}
