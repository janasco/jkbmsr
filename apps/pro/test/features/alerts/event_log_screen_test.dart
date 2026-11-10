// The event log is one timeline over three independent sources. These tests
// pin the merge order, that an entry expands to its own detail, and — the
// failure mode the screen exists to avoid — that a source which could not be
// read is stated rather than silently producing a shorter history.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jkbmsr_pro/features/alerts/alerts_screen.dart';
import 'package:jkbmsr_pro/services/api_client.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _resolvedAlert() => {
      'id': 'a1',
      'deviceId': 'gw-1',
      'deviceName': 'Home Battery',
      'severity': 'warning',
      'message': 'Over-voltage a1',
      'createdAt': '2026-09-01 10:00:00',
      'isResolved': true,
      'resolvedAt': '2026-09-01 10:30:00',
    };

Map<String, dynamic> _device() => {
      'id': 'gw-1',
      'name': 'Home Battery',
      'status': 'online',
      'lastSeen': '2026-09-01 12:00:00',
    };

Map<String, dynamic> _bleEvent() => {
      'timestamp': '2026-09-01T12:00:00Z',
      'address': 'AA:BB:CC:DD:EE:FF',
      'advertisedName': 'JK-BMS',
      'rssi': -61,
      'hardwareVersion': '11A',
      'softwareVersion': '11.55',
      'framesDecoded': 42,
      'readOnly': true,
    };

Map<String, dynamic> _otaEvent() => {
      'id': 7,
      'lastResult': 'success',
      'offeredVersion': '0.9.10',
      'lastCheckSucceeded': true,
      'updateAvailable': true,
      'updateApplied': false,
      'createdAt': '2026-09-01 11:00:00',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  void stub({
    http.Response Function()? alerts,
    http.Response Function()? devices,
    http.Response Function()? ble,
    http.Response Function()? ota,
  }) {
    APIClient.configure(
      baseUrl: 'https://test.local',
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/ble/history')) {
          return ble?.call() ?? _json({'events': [_bleEvent()]}, 200);
        }
        if (path.endsWith('/ota/history')) {
          return ota?.call() ?? _json({'events': [_otaEvent()]}, 200);
        }
        if (path.endsWith('/alerts')) {
          return alerts?.call() ??
              _json({
                'alerts': [_resolvedAlert()],
                'hasMore': false,
              }, 200);
        }
        if (path == '/v1/dashboard/devices') {
          return devices?.call() ??
              _json({
                'devices': [_device()],
              }, 200);
        }
        if (path == '/v1/dashboard/devices/gw-1') {
          return _json({
            'device': _device(),
            'telemetry': <String, dynamic>{},
          }, 200);
        }
        return _json({}, 200);
      }),
    );
  }

  Future<void> pumpEventLog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: const AlertsScreen(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Event log'));
    await tester.pumpAndSettle();
  }

  testWidgets('merges alerts, BLE sessions and firmware events newest first',
      (tester) async {
    stub();
    await pumpEventLog(tester);

    expect(find.text('Over-voltage a1'), findsOneWidget);
    expect(find.textContaining('Connected to JK-BMS'), findsOneWidget);
    expect(find.text('Firmware 0.9.10 is available'), findsOneWidget);

    final bleY =
        tester.getTopLeft(find.textContaining('Connected to JK-BMS')).dy;
    final otaY =
        tester.getTopLeft(find.text('Firmware 0.9.10 is available')).dy;
    final alertY = tester.getTopLeft(find.text('Over-voltage a1')).dy;
    expect(bleY, lessThan(otaY));
    expect(otaY, lessThan(alertY));

    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a BLE entry expands to its own detail', (tester) async {
    stub();
    await pumpEventLog(tester);

    expect(find.text('AA:BB:CC:DD:EE:FF'), findsNothing);

    await tester.tap(find.textContaining('Connected to JK-BMS'));
    await tester.pumpAndSettle();

    expect(find.text('AA:BB:CC:DD:EE:FF'), findsOneWidget);
    expect(find.text('-61 dBm'), findsOneWidget);
    expect(find.text('11A'), findsOneWidget);
    expect(find.text('11.55'), findsOneWidget);
    expect(find.text('Read-only'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('an alert entry expands to severity, message and resolved time',
      (tester) async {
    stub();
    await pumpEventLog(tester);

    await tester.tap(find.text('Over-voltage a1'));
    await tester.pumpAndSettle();

    expect(find.text('Severity'), findsOneWidget);
    expect(find.text('Warning'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    expect(find.text('Resolved'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a failed source is named while the other sources still render',
      (tester) async {
    stub(alerts: () => _json({'error': 'upstream unavailable'}, 500));
    await pumpEventLog(tester);

    expect(find.text('This log is incomplete'), findsOneWidget);
    expect(find.textContaining('Resolved alerts could not be read'),
        findsOneWidget);
    expect(find.textContaining('Connected to JK-BMS'), findsOneWidget);
    expect(find.text('Firmware 0.9.10 is available'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('one unreadable gateway narrows the source and says so',
      (tester) async {
    stub(
      devices: () => _json({
        'devices': [
          _device(),
          {
            'id': 'gw-2',
            'name': 'Garage Battery',
            'status': 'online',
            'lastSeen': '2026-09-01 12:00:00',
          },
        ],
      }, 200),
      ble: () => _json({'error': 'unavailable'}, 500),
    );
    await pumpEventLog(tester);

    expect(find.text('This log is incomplete'), findsOneWidget);
    expect(
      find.textContaining(
          'Gateway connections could not be read from 2 of 2 gateways'),
      findsOneWidget,
    );
    expect(find.text('Firmware 0.9.10 is available'), findsWidgets);

    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('an empty log says nothing has happened, not that it failed',
      (tester) async {
    stub(
      alerts: () => _json({'alerts': <Object>[], 'hasMore': false}, 200),
      devices: () => _json({'devices': <Object>[]}, 200),
    );
    await pumpEventLog(tester);

    expect(find.text('Nothing has happened yet'), findsOneWidget);
    expect(find.textContaining('could not be read'), findsNothing);
    expect(find.text('Try Again'), findsNothing);

    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('when every source fails the log says so and offers a retry',
      (tester) async {
    stub(
      alerts: () => _json({'error': 'unavailable'}, 500),
      devices: () => _json({'error': 'unavailable'}, 500),
    );
    await pumpEventLog(tester);

    expect(find.text('No events could be loaded'), findsOneWidget);
    expect(find.textContaining('Resolved alerts could not be read'),
        findsOneWidget);
    expect(find.textContaining('Gateway connections could not be read'),
        findsOneWidget);
    expect(find.textContaining('Firmware update events could not be read'),
        findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('Nothing has happened yet'), findsNothing);

    await tester.pump(const Duration(seconds: 6));
  });
}
