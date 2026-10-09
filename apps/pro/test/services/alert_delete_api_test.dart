// Unit tests for the two new alert-deletion client methods. The HTTP layer is
// mocked at the http.Client seam (same seam APIClient.configure injects).
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

  group('deleteAlert', () {
    test('sends DELETE to /alerts/:id and returns the deleted id', () async {
      late http.Request captured;
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient((request) async {
          captured = request;
          return _json({'ok': true, 'deleted': 'a1'}, 200);
        }),
      );

      final deleted = await APIClient().deleteAlert('a1');

      expect(captured.method, 'DELETE');
      expect(captured.url.path, '/v1/dashboard/alerts/a1');
      expect(deleted, 'a1');
    });

    test('surfaces the server error message', () async {
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient(
          (request) async => _json({'error': 'Alert not found'}, 404),
        ),
      );

      await expectLater(
        APIClient().deleteAlert('missing'),
        throwsA(predicate((e) => e.toString().contains('Alert not found'))),
      );
    });
  });

  group('deleteResolvedAlerts', () {
    test('sends DELETE to /alerts/resolved and returns deletedCount', () async {
      late http.Request captured;
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient((request) async {
          captured = request;
          return _json({'ok': true, 'deletedCount': 7}, 200);
        }),
      );

      final count = await APIClient().deleteResolvedAlerts();

      expect(captured.method, 'DELETE');
      expect(captured.url.path, '/v1/dashboard/alerts/resolved');
      expect(captured.url.queryParameters, isEmpty);
      expect(count, 7);
    });

    test('scopes the delete to a gateway when a deviceId is given', () async {
      late http.Request captured;
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient((request) async {
          captured = request;
          return _json({'ok': true, 'deletedCount': 2}, 200);
        }),
      );

      final count = await APIClient().deleteResolvedAlerts(deviceId: 'gw-1');

      expect(captured.method, 'DELETE');
      expect(captured.url.path, '/v1/dashboard/alerts/resolved');
      expect(captured.url.queryParameters['deviceId'], 'gw-1');
      expect(count, 2);
    });

    test('surfaces the server error message', () async {
      APIClient.configure(
        baseUrl: 'https://test.local',
        client: MockClient(
          (request) async => _json({'error': 'Forbidden'}, 403),
        ),
      );

      await expectLater(
        APIClient().deleteResolvedAlerts(),
        throwsA(predicate((e) => e.toString().contains('Forbidden'))),
      );
    });
  });
}
