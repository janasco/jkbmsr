// Widget coverage for the persistent remote Wi-Fi target surfaced inside the
// existing Settings → WiFi category. The screen is offline-pumpable by
// injecting a mock http.Client into the APIClient singleton (same seam the
// back-button/settings tests use); package_info_plus is stubbed because the
// screen kicks off plugin-backed loads in initState.
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

const _ssidKey = ValueKey('remote-wifi-target-ssid');
const _passwordKey = ValueKey('remote-wifi-target-password');
const _setKey = ValueKey('remote-wifi-target-set');
const _clearKey = ValueKey('remote-wifi-target-clear');

void _stubPlugins() {
  SharedPreferences.setMockInitialValues({});
  const packageChannel = MethodChannel('dev.fluttercommunity.plus/package_info');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(packageChannel, (call) async {
    if (call.method == 'getAll') {
      return <String, dynamic>{
        'appName': 'JK BMS Remote',
        'packageName': 'com.jkbmsr.pro',
        'version': '1.3.41',
        'buildNumber': '73',
        'buildSignature': '',
      };
    }
    return null;
  });
}

Map<String, dynamic> _device() => {
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
    };

Map<String, dynamic> _securedTarget(String ssid) => {
      'ssid': ssid,
      'isOpen': false,
      'revision': 'rev-1',
      'setAt': '2026-10-09 12:00:00',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, dynamic>? target;
  late http.Request? lastPut;
  late http.Request? lastDelete;
  // When true the target route answers 404, exercising the "route absent /
  // load failed" path.
  late bool targetRouteAbsent;

  setUp(() {
    _stubPlugins();
    target = null;
    lastPut = null;
    lastDelete = null;
    targetRouteAbsent = false;
  });

  void stubApi() {
    APIClient.configure(
      baseUrl: 'https://test.local',
      client: MockClient((request) async {
        final path = request.url.path;
        final method = request.method;

        if (path == '/api/v1/dashboard/devices') {
          return _json({'devices': [_device()]}, 200);
        }
        if (path == '/api/v1/dashboard/devices/gw-1/config') {
          return _json({'config': <String, dynamic>{}}, 200);
        }
        if (path == '/api/v1/dashboard/devices/gw-1/shares') {
          return _json({'shares': [], 'maxShares': 5}, 200);
        }
        if (path == '/api/v1/dashboard/devices/gw-1/wifi') {
          return _json({
            'wifi': {
              'currentSsid': 'OldNet',
              'networks': [],
              'changeStatus': 'idle',
              'changeMessage': '',
            },
          }, 200);
        }
        if (path == '/api/v1/dashboard/devices/gw-1/wifi/target') {
          if (targetRouteAbsent) return _json({'error': 'Not found'}, 404);
          if (method == 'PUT') {
            lastPut = request;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            target = {
              'ssid': body['ssid'],
              'isOpen': body['isOpen'],
              'revision': 'rev-2',
              'setAt': '2026-10-09 13:00:00',
            };
            return _json({'target': target, 'status': 'pending'}, 200);
          }
          if (method == 'DELETE') {
            lastDelete = request;
            target = null;
            return _json({'cleared': true}, 200);
          }
          return _json({
            'target': target,
            'reported': {
              'ssid': 'OldNet',
              'state': 'auth_failed',
              'error': 'handshake timeout',
              'at': '2026-10-09 12:30:00',
              'localProvisioned': false,
            },
            'alert': {
              'active': target != null,
              'lastSentAt': target != null ? '2026-10-09 12:35:00' : null,
              'count': target != null ? 2 : 0,
            },
          }, 200);
        }
        if (path == '/api/v1/user/sessions') {
          return _json({'logins': []}, 200);
        }
        return _json({'error': 'not found'}, 404);
      }),
    );
  }

  Future<void> pumpWifi(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    stubApi();
    await tester.pumpWidget(MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: const SettingsScreen(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('WiFi'));
    await tester.pumpAndSettle();
  }

  Future<void> drainTimers(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
  }

  testWidgets('shows the remote target, its alert, and the last reported state',
      (tester) async {
    target = _securedTarget('HomeNet');
    await pumpWifi(tester);

    expect(find.text('Remote WiFi target'), findsOneWidget);
    expect(find.text('HomeNet'), findsOneWidget);
    expect(find.text('Secured'), findsOneWidget);
    expect(find.text('Password stored encrypted — it is never shown again.'), findsOneWidget);

    // The gateway is still on the old network and reported the failure.
    expect(find.text('Last reported by the gateway'), findsOneWidget);
    expect(find.text('Wrong password — OldNet'), findsOneWidget);
    expect(find.text('handshake timeout'), findsOneWidget);

    // The unreachable-alert episode is surfaced with the offline explanation.
    expect(find.textContaining("hasn't reached this network yet"), findsOneWidget);
    expect(find.textContaining("alerted you 2 times"), findsOneWidget);

    // The card offers both set and clear.
    expect(find.byKey(_setKey), findsOneWidget);
    expect(find.byKey(_clearKey), findsOneWidget);

    await drainTimers(tester);
  });

  testWidgets('the open-network toggle removes the password field entirely',
      (tester) async {
    target = _securedTarget('HomeNet');
    await pumpWifi(tester);

    expect(find.byKey(_passwordKey), findsOneWidget);

    await tester.tap(find.text('Open network'));
    await tester.pumpAndSettle();

    expect(find.byKey(_passwordKey), findsNothing);
    expect(find.text('No password will be sent for an open network.'), findsOneWidget);

    await drainTimers(tester);
  });

  testWidgets('setting a secured target confirms the encrypted send and PUTs it',
      (tester) async {
    await pumpWifi(tester);

    // No target yet: the card says so and only offers set.
    expect(find.text('No remote target set. The gateway keeps using its current network.'), findsOneWidget);
    expect(find.byKey(_clearKey), findsNothing);

    await tester.enterText(find.byKey(_ssidKey), 'NewNet');
    await tester.enterText(find.byKey(_passwordKey), 's3cret');
    await tester.tap(find.byKey(_setKey));
    await tester.pumpAndSettle();

    // Security-sensitive path: an explicit confirmation that says the password
    // is stored encrypted and never shown again, plus the offline wording.
    expect(find.text('Set remote WiFi target?'), findsOneWidget);
    expect(find.textContaining('stored encrypted on the server'), findsOneWidget);
    expect(find.textContaining('never shown again'), findsOneWidget);
    expect(find.textContaining('next check-in'), findsWidgets);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Set'));
    await tester.pumpAndSettle();

    expect(lastPut, isNotNull);
    expect(jsonDecode(lastPut!.body), {
      'ssid': 'NewNet',
      'password': 's3cret',
      'isOpen': false,
    });
    expect(find.textContaining('Remote WiFi target saved'), findsOneWidget);

    // The cleared field and the never-echoed password: the app does not show
    // the stored password back anywhere.
    expect(
      tester.widget<TextField>(find.byKey(_passwordKey)).controller!.text,
      isEmpty,
    );
    expect(find.text('s3cret'), findsNothing);
    expect(find.text('NewNet'), findsOneWidget);

    await drainTimers(tester);
  });

  testWidgets('the open-network path sends no password and is labelled OPEN',
      (tester) async {
    await pumpWifi(tester);

    await tester.tap(find.text('Open network'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_ssidKey), 'CafeGuest');
    await tester.tap(find.byKey(_setKey));
    await tester.pumpAndSettle();

    expect(find.textContaining('OPEN network with no password'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Set'));
    await tester.pumpAndSettle();

    expect(jsonDecode(lastPut!.body), {
      'ssid': 'CafeGuest',
      'password': '',
      'isOpen': true,
    });
    expect(find.text('CafeGuest'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('No password. Anyone nearby can join this network.'), findsOneWidget);

    await drainTimers(tester);
  });

  testWidgets('clearing the target confirms, DELETEs, and returns to the empty state',
      (tester) async {
    target = _securedTarget('HomeNet');
    await pumpWifi(tester);

    await tester.tap(find.byKey(_clearKey));
    await tester.pumpAndSettle();

    expect(find.text('Clear remote WiFi target?'), findsOneWidget);
    expect(find.textContaining('keeps the network it is currently on'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Clear'));
    await tester.pumpAndSettle();

    expect(lastDelete, isNotNull);
    expect(lastDelete!.url.path, '/api/v1/dashboard/devices/gw-1/wifi/target');
    expect(find.text('No remote target set. The gateway keeps using its current network.'), findsOneWidget);
    expect(find.byKey(_clearKey), findsNothing);

    await drainTimers(tester);
  });

  testWidgets('degrades gracefully when the target route is unavailable',
      (tester) async {
    targetRouteAbsent = true;
    await pumpWifi(tester);

    expect(find.text('Remote target settings are unavailable right now.'), findsOneWidget);
    // The set control is disabled rather than offering a dead action.
    expect(tester.widget<ElevatedButton>(find.byKey(_setKey)).onPressed, isNull);

    await drainTimers(tester);
  });
}
