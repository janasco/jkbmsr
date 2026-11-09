import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jkbmsr_pro/features/battery/battery_dashboard_screen.dart';
import 'package:jkbmsr_pro/services/api_client.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _deviceId = 'jkbmsr-dashboard-activity';

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _deviceJson() => {
      'id': _deviceId,
      'name': 'Test pack',
      'status': 'online',
      'targetHardware': 'esp32-s3-16mb',
      'otaChannel': 'stable',
      'soc': 84,
      'voltage': 53.2,
      'current': -12.4,
      'lastSeen': DateTime.now().toUtc().toIso8601String(),
      'updateAvailable': false,
      'dashboardTemplateMobile': 'default',
      // Shared viewer: skips the owner-only alert-state request, which is not
      // part of the loading path under test.
      'isOwner': false,
    };

Map<String, dynamic> _telemetryJson() => {
      'voltage': 53.2,
      'current': -12.4,
      'power': 660.2,
      'soc': 84,
      'temperature1': 22.4,
      'temperature2': 21.8,
      'cells': [
        for (var i = 0; i < 16; i++) {'cell': i + 1, 'voltage': 3.327},
      ],
      'bms': <String, dynamic>{},
      'diagnostics': <String, dynamic>{},
    };

/// A stubbed API whose two loading requests can be held open independently,
/// so a test can observe the screen while each one is genuinely in flight.
class _PendingApi {
  final List<Completer<http.Response>> deviceLists = [];
  final List<Completer<http.Response>> deviceDetails = [];

  http.Client client() => MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/v1/dashboard/devices')) {
          final completer = Completer<http.Response>();
          deviceLists.add(completer);
          return completer.future;
        }
        if (path.endsWith('/config')) {
          return _json({
            'config': {
              'batteryAnimationsEnabled': false,
              'telemetryIntervalSeconds': 3600,
            },
          });
        }
        if (path.endsWith('/ble/history')) return _json({'events': <dynamic>[]});
        if (path.endsWith('/telemetry/history')) return _json({'points': <dynamic>[]});
        if (path.endsWith('/wifi/target')) return _json({'target': null});
        if (path.endsWith('/$_deviceId')) {
          final completer = Completer<http.Response>();
          deviceDetails.add(completer);
          return completer.future;
        }
        return _json(<String, dynamic>{});
      });
}

Future<void> _mount(WidgetTester tester, {String? deviceId}) async {
  await tester.pumpWidget(MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    home: BatteryDashboardScreen(deviceId: deviceId),
  ));
  await tester.pump();
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // The dedupe layer arms a 5 s TTL timer per request; drain it on the fake
  // clock so the test does not end with a pending timer.
  await tester.pump(const Duration(seconds: 6));
}

void _completeDetail(_PendingApi api, int index) {
  api.deviceDetails[index].complete(
        _json({'device': _deviceJson(), 'telemetry': _telemetryJson()}),
      );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('first load names the telemetry request until the dashboard lands',
      (tester) async {
    final api = _PendingApi();
    APIClient.configure(baseUrl: 'https://test.local', client: api.client());

    await _mount(tester, deviceId: _deviceId);

    expect(api.deviceDetails, hasLength(1));
    expect(find.text('Reading telemetry…'), findsOneWidget);
    expect(find.text('Test pack'), findsNothing);

    api.deviceDetails.single.complete(
      _json({'device': _deviceJson(), 'telemetry': _telemetryJson()}),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Reading telemetry…'), findsNothing);
    expect(find.text('Test pack'), findsWidgets);

    await _dispose(tester);
  });

  testWidgets('a dashboard opened without an id names the gateway lookup first',
      (tester) async {
    final api = _PendingApi();
    APIClient.configure(baseUrl: 'https://test.local', client: api.client());

    await _mount(tester);

    expect(api.deviceLists, hasLength(1));
    expect(find.text('Finding your gateway…'), findsOneWidget);

    api.deviceLists.single.complete(
      _json({'devices': [_deviceJson()]}),
    );
    await tester.pump();
    await tester.pump();

    // The list is no longer what the screen is waiting on.
    expect(find.text('Finding your gateway…'), findsNothing);
    expect(find.text('Reading telemetry…'), findsOneWidget);
    expect(api.deviceDetails, hasLength(1));

    _completeDetail(api, 0);
    await tester.pump();
    await tester.pump();

    expect(find.text('Test pack'), findsWidgets);

    await _dispose(tester);
  });

  testWidgets('a pull-to-refresh keeps the dashboard visible and names itself',
      (tester) async {
    final api = _PendingApi();
    APIClient.configure(baseUrl: 'https://test.local', client: api.client());

    await _mount(tester, deviceId: _deviceId);
    _completeDetail(api, 0);
    await tester.pump();
    await tester.pump();

    expect(find.text('Test pack'), findsWidgets);
    expect(find.text('Refreshing…'), findsNothing);

    tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
    await tester.pump();
    // The indicator snaps into view before it invokes onRefresh.
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.deviceDetails, hasLength(2));
    expect(find.text('Refreshing…'), findsOneWidget);
    // The loaded dashboard stays on screen instead of being replaced by the
    // skeleton.
    expect(find.text('Test pack'), findsWidgets);

    _completeDetail(api, 1);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Refreshing…'), findsNothing);
    expect(find.text('Test pack'), findsWidgets);

    await _dispose(tester);
  });
}
