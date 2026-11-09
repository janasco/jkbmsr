// Widget coverage for the Settings → Support entry that points owners at the
// JK BMS Contributor app. The launcher is injected, so the exact Play URL and
// the failure path are both asserted without a platform channel.
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

void _stubPlugins() {
  SharedPreferences.setMockInitialValues({});
  const packageChannel = MethodChannel('dev.fluttercommunity.plus/package_info');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(packageChannel, (call) async {
    if (call.method == 'getAll') {
      return <String, dynamic>{
        'appName': 'JK BMS Remote',
        'packageName': 'com.jkbmsr.pro',
        'version': '1.3.44',
        'buildNumber': '76',
        'buildSignature': '',
      };
    }
    return null;
  });
}

void _stubApi() {
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

const _contributorUrl =
    'https://play.google.com/store/apps/details?id=com.jkbmsr.contributor';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _stubPlugins();
    _stubApi();
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    required Future<bool> Function(Uri uri) launcher,
  }) async {
    tester.view.physicalSize = const Size(400, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: SettingsScreen(externalLinkLauncher: launcher),
    ));
    await tester.pumpAndSettle();
  }

  // The config load keeps a request-deduplication timer alive for a few
  // seconds; let it expire so it cannot outlive the disposed widget tree.
  Future<void> drainTimers(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
  }

  testWidgets('tapping the Contributor entry opens the exact Play listing URL',
      (tester) async {
    Uri? requested;
    await pumpSettings(tester, launcher: (uri) async {
      requested = uri;
      return true;
    });

    expect(find.text('JK BMS Contributor'), findsOneWidget);

    await tester.tap(find.text('JK BMS Contributor'));
    await tester.pumpAndSettle();

    expect(requested, isNotNull);
    expect(requested.toString(), _contributorUrl);
    // A successful launch stays quiet — no error message on screen.
    expect(find.textContaining('Could not open the Play Store'), findsNothing);

    await drainTimers(tester);
  });

  testWidgets('a launcher that returns false shows the URL and does not throw',
      (tester) async {
    await pumpSettings(tester, launcher: (uri) async => false);

    await tester.tap(find.text('JK BMS Contributor'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining(_contributorUrl), findsOneWidget);

    await drainTimers(tester);
  });

  testWidgets('a launcher that throws is reported instead of escaping',
      (tester) async {
    await pumpSettings(
      tester,
      launcher: (uri) async => throw PlatformException(code: 'no-store'),
    );

    await tester.tap(find.text('JK BMS Contributor'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining(_contributorUrl), findsOneWidget);

    await drainTimers(tester);
  });
}
