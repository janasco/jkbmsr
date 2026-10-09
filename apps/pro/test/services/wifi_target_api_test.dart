// Unit tests for the persistent remote Wi-Fi target client methods. The HTTP
// layer is mocked at the http.Client seam (same seam APIClient.configure
// injects), so nothing here touches the network.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jkbmsr_pro/services/api_client.dart';

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('getDeviceWifiTarget', () {
    test('GETs the target route and parses target/reported/alert', () async {
      late http.Request captured;
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient((request) async {
          captured = request;
          return _json({
            'target': {
              'ssid': 'HomeNet',
              'isOpen': false,
              'revision': 'rev-1',
              'setAt': '2026-10-09 12:00:00',
            },
            'reported': {
              'ssid': 'OldNet',
              'state': 'auth_failed',
              'error': 'handshake timeout',
              'at': '2026-10-09 12:30:00',
              'localProvisioned': false,
            },
            'alert': {'active': true, 'lastSentAt': '2026-10-09 12:35:00', 'count': 2},
          }, 200);
        }),
      );

      final state = await APIClient().getDeviceWifiTarget('gw-1');

      expect(captured.method, 'GET');
      expect(captured.url.path, '/v1/dashboard/devices/gw-1/wifi/target');
      expect(state.target!.ssid, 'HomeNet');
      expect(state.target!.isOpen, isFalse);
      expect(state.target!.revision, 'rev-1');
      expect(state.reported!.stateLabel, 'Wrong password');
      expect(state.reported!.error, 'handshake timeout');
      expect(state.alert.active, isTrue);
      expect(state.alert.count, 2);
    });

    test('parses a null target and null reported as absent', () async {
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient(
          (request) async => _json({
            'target': null,
            'reported': null,
            'alert': {'active': false, 'lastSentAt': null, 'count': 0},
          }, 200),
        ),
      );

      final state = await APIClient().getDeviceWifiTarget('gw-1');

      expect(state.target, isNull);
      expect(state.reported, isNull);
      expect(state.alert.active, isFalse);
      expect(state.alert.count, 0);
    });

    test('surfaces the server error message', () async {
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient(
          (request) async => _json({'error': 'Device not found'}, 404),
        ),
      );

      await expectLater(
        APIClient().getDeviceWifiTarget('missing'),
        throwsA(predicate((e) => e.toString().contains('Device not found'))),
      );
    });
  });

  group('setDeviceWifiTarget', () {
    test('PUTs the secured target and sends the password once', () async {
      late http.Request captured;
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient((request) async {
          captured = request;
          return _json({
            'target': {'ssid': 'NewNet', 'isOpen': false, 'revision': 'rev-2'},
            'status': 'pending',
          }, 200);
        }),
      );

      await APIClient().setDeviceWifiTarget('gw-1', ssid: 'NewNet', password: 's3cret');

      expect(captured.method, 'PUT');
      expect(captured.url.path, '/v1/dashboard/devices/gw-1/wifi/target');
      expect(jsonDecode(captured.body), {
        'ssid': 'NewNet',
        'password': 's3cret',
        'isOpen': false,
      });
    });

    test('open network sends isOpen true and an empty password', () async {
      late http.Request captured;
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient((request) async {
          captured = request;
          return _json({
            'target': {'ssid': 'CafeGuest', 'isOpen': true, 'revision': 'rev-3'},
            'status': 'pending',
          }, 200);
        }),
      );

      // A stray password is deliberately ignored on the open path.
      await APIClient().setDeviceWifiTarget('gw-1', ssid: 'CafeGuest', password: 'ignored', isOpen: true);

      expect(jsonDecode(captured.body), {
        'ssid': 'CafeGuest',
        'password': '',
        'isOpen': true,
      });
    });

    test('surfaces the server validation error', () async {
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient(
          (request) async => _json({'error': 'SSID must be between 1 and 32 characters'}, 400),
        ),
      );

      await expectLater(
        APIClient().setDeviceWifiTarget('gw-1', ssid: '', password: 'x'),
        throwsA(predicate((e) => e.toString().contains('SSID must be between 1 and 32 characters'))),
      );
    });
  });

  group('clearDeviceWifiTarget', () {
    test('DELETEs the target route', () async {
      late http.Request captured;
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient((request) async {
          captured = request;
          return _json({'cleared': true}, 200);
        }),
      );

      await APIClient().clearDeviceWifiTarget('gw-1');

      expect(captured.method, 'DELETE');
      expect(captured.url.path, '/v1/dashboard/devices/gw-1/wifi/target');
    });

    test('surfaces the server error message', () async {
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient(
          (request) async => _json({'error': 'Forbidden'}, 403),
        ),
      );

      await expectLater(
        APIClient().clearDeviceWifiTarget('gw-1'),
        throwsA(predicate((e) => e.toString().contains('Forbidden'))),
      );
    });
  });
}
