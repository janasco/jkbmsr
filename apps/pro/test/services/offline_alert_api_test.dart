// Unit tests for the owner-side offline-alert control client methods. The HTTP
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

  group('acknowledgeDeviceOfflineAlerts', () {
    test('POSTs the acknowledge route and returns the echoed value', () async {
      late http.Request captured;
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient((request) async {
          captured = request;
          return _json({'acknowledged': true}, 200);
        }),
      );

      final acknowledged = await APIClient().acknowledgeDeviceOfflineAlerts('gw-1');

      expect(captured.method, 'POST');
      expect(captured.url.path, '/v1/dashboard/devices/gw-1/alerts/acknowledge');
      expect(acknowledged, isTrue);
    });

    test('adopts the server echoed false rather than assuming success', () async {
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient((request) async => _json({'acknowledged': false}, 200)),
      );

      expect(await APIClient().acknowledgeDeviceOfflineAlerts('gw-1'), isFalse);
    });

    test('surfaces the server error message', () async {
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient((request) async => _json({'error': 'Forbidden'}, 403)),
      );

      await expectLater(
        APIClient().acknowledgeDeviceOfflineAlerts('gw-1'),
        throwsA(predicate((e) => e.toString().contains('Forbidden'))),
      );
    });
  });

  group('clearDeviceOfflineAlertsAcknowledge', () {
    test('DELETEs the acknowledge route and returns the echoed false', () async {
      late http.Request captured;
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient((request) async {
          captured = request;
          return _json({'acknowledged': false}, 200);
        }),
      );

      final acknowledged = await APIClient().clearDeviceOfflineAlertsAcknowledge('gw-1');

      expect(captured.method, 'DELETE');
      expect(captured.url.path, '/v1/dashboard/devices/gw-1/alerts/acknowledge');
      expect(acknowledged, isFalse);
    });

    test('a 404 (route not deployed) degrades to AlertActionUnavailableException', () async {
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient((request) async => _json({'error': 'Not found'}, 404)),
      );

      await expectLater(
        APIClient().clearDeviceOfflineAlertsAcknowledge('gw-1'),
        throwsA(isA<AlertActionUnavailableException>()),
      );
    });

    test('a 405 degrades the same way', () async {
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient((request) async => _json({'error': 'Method not allowed'}, 405)),
      );

      await expectLater(
        APIClient().clearDeviceOfflineAlertsAcknowledge('gw-1'),
        throwsA(isA<AlertActionUnavailableException>()),
      );
    });

    test('a genuine failure message still surfaces', () async {
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient((request) async => _json({'error': 'Device not found'}, 400)),
      );

      await expectLater(
        APIClient().clearDeviceOfflineAlertsAcknowledge('gw-1'),
        throwsA(predicate((e) => e.toString().contains('Device not found'))),
      );
    });
  });

  group('setDeviceOfflineAlertsMuted', () {
    test('PUTs {muted: true} and returns the echoed value', () async {
      late http.Request captured;
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient((request) async {
          captured = request;
          return _json({'muted': true}, 200);
        }),
      );

      final muted = await APIClient().setDeviceOfflineAlertsMuted('gw-1', muted: true);

      expect(captured.method, 'PUT');
      expect(captured.url.path, '/v1/dashboard/devices/gw-1/alerts/mute');
      expect(jsonDecode(captured.body), {'muted': true});
      expect(muted, isTrue);
    });

    test('unmuting sends {muted: false}', () async {
      late http.Request captured;
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient((request) async {
          captured = request;
          return _json({'muted': false}, 200);
        }),
      );

      final muted = await APIClient().setDeviceOfflineAlertsMuted('gw-1', muted: false);

      expect(jsonDecode(captured.body), {'muted': false});
      expect(muted, isFalse);
    });

    test('adopts the server echoed value even when it differs from the request', () async {
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient((request) async => _json({'muted': false}, 200)),
      );

      // Asked to mute, server says it stayed unmuted — the caller must trust
      // the echoed value, not the request.
      expect(
        await APIClient().setDeviceOfflineAlertsMuted('gw-1', muted: true),
        isFalse,
      );
    });
  });
}
