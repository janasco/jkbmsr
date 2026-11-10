// Wiring test: the Cell Voltages screen feeds the explainer from the same
// telemetry it renders, and omits it entirely when the readings cannot support
// a comparison.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jkbmsr_pro/features/battery/cell_voltages_screen.dart';
import 'package:jkbmsr_pro/features/battery/widgets/cell_insight_panel.dart';
import 'package:jkbmsr_pro/services/api_client.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _device() => {
      'id': 'gw-1',
      'name': 'Garage pack',
      'status': 'online',
      'targetHardware': 'esp32-s3-16mb',
      'otaChannel': 'stable',
      'soc': 84,
      'voltage': 53.2,
      'current': -12.0,
      'lastSeen': '2026-11-09 10:00:00',
      'updateAvailable': false,
      'expectedIntervalSeconds': 60,
      'secondsSinceLastTelemetry': 12,
      'isOwner': true,
    };

Map<String, dynamic> _telemetry(List<Map<String, dynamic>> cells) => {
      'voltage': 53.2,
      'current': -12.0,
      'power': 638.4,
      'soc': 84,
      'temperature1': 22.0,
      'temperature2': 22.4,
      'cells': cells,
      'bms': {
        'fullCapacityAh': 100.0,
        'charging': false,
        'discharging': true,
        'balancing': true,
        'balancingCurrent': 0.05,
      },
      'diagnostics': {'bmsLinkUp': true},
    };

Future<void> _pumpScreen(
  WidgetTester tester, {
  required List<Map<String, dynamic>> cells,
}) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  APIClient.configure(
    baseUrl: 'https://test.local',
    client: MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/config')) {
        return _json({
          'config': {
            'telemetryIntervalSeconds': 30,
            'batteryAnimationsEnabled': false,
          },
        }, 200);
      }
      if (path.contains('/dashboard/devices/')) {
        return _json({
          'device': _device(),
          'telemetry': _telemetry(cells),
        }, 200);
      }
      if (path.endsWith('/dashboard/devices')) {
        return _json({
          'devices': [_device()],
        }, 200);
      }
      return _json({}, 200);
    }),
  );

  await tester.pumpWidget(MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    home: const CellVoltagesScreen(deviceId: 'gw-1'),
  ));
  await tester.pumpAndSettle();
}

Future<void> _disposeScreen(WidgetTester tester) async {
  // The screen owns a periodic poll timer; removing it cancels the timer.
  // The API client's request-dedupe window is a separate one-shot timer and
  // still has to be allowed to expire.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('explains the readings on the same screen without changing them',
      (tester) async {
    await _pumpScreen(tester, cells: const [
      {'cell': 1, 'voltage': 3.297},
      {'cell': 2, 'voltage': 3.292},
      {'cell': 3, 'voltage': 3.297},
      {'cell': 4, 'voltage': 3.297},
      {'cell': 5, 'voltage': 3.305},
    ]);

    expect(find.byType(CellInsightPanel), findsOneWidget);
    expect(
      find.text('Spread 13 mV · weakest cell #2, strongest #5'),
      findsOneWidget,
    );
    expect(
      find.text('Within the balanced range · balancing at 0.05 A'),
      findsOneWidget,
    );
    // The existing grid is still rendered alongside it.
    expect(find.text('Cell balance · 5S'), findsOneWidget);
    expect(find.text('3.305 V'), findsOneWidget);

    await _disposeScreen(tester);
  });

  testWidgets('does not explain readings the API did not provide',
      (tester) async {
    await _pumpScreen(tester, cells: const [
      {'cell': 1, 'voltage': 0},
      {'cell': 2, 'voltage': 0},
    ]);

    expect(find.byType(CellInsightPanel), findsNothing);
    expect(find.textContaining('Spread'), findsNothing);

    await _disposeScreen(tester);
  });

  testWidgets('tapping a cell row opens that cell in the detail sheet',
      (tester) async {
    await _pumpScreen(tester, cells: const [
      {'cell': 1, 'voltage': 3.297},
      {'cell': 2, 'voltage': 3.292},
      {'cell': 3, 'voltage': 3.297},
      {'cell': 4, 'voltage': 3.297},
      {'cell': 5, 'voltage': 3.305},
    ]);

    await tester.tap(find.text('3.292 V'));
    await tester.pumpAndSettle();

    expect(find.text('Cell 2'), findsOneWidget);
    expect(find.text('Weakest cell in the pack'), findsOneWidget);
    expect(find.text('6 mV below average'), findsOneWidget);
    expect(find.text('13 mV · Balanced'), findsOneWidget);
    expect(find.text('0.05 A'), findsOneWidget);
    expect(find.text('No per-cell history'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Weakest cell in the pack'), findsNothing);

    await _disposeScreen(tester);
  });
}
