import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/features/battery/widgets/bms_link_banner.dart';
import 'package:jkbmsr_pro/models/telemetry.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/components.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

const _title = 'Gateway online — no data from the BMS';

Telemetry _telemetry(Map<String, dynamic> diagnostics) {
  return Telemetry(
    voltage: 0,
    current: 0,
    power: 0,
    soc: 0,
    temperature1: 0,
    temperature2: 0,
    cells: const [],
    bms: BmsExtras(
      mosfetTemperature: 0,
      minCellVoltage: 0,
      maxCellVoltage: 0,
      avgCellVoltage: 0,
      deltaCellVoltage: 0,
      minVoltageCell: 0,
      maxVoltageCell: 0,
      cycleCount: 0,
      cycleCapacityAh: 0,
      fullCapacityAh: 0,
      remainingCapacityAh: 0,
      stateOfHealth: null,
      balancingCurrent: 0,
      balancing: false,
      charging: false,
      discharging: false,
      errorsBitmask: 0,
    ),
    diagnostics: diagnostics,
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('link down -> banner, with the last error and signal', (tester) async {
    await tester.pumpWidget(_wrap(BmsLinkBanner(
      telemetry: _telemetry({
        'bmsLinkUp': false,
        'bytesReceived': 0,
        'parser': {'bytesReceived': 0},
        'ble': {
          'state': 'connection_failed',
          'rssi': -91,
          'lastError': 'BLE connection failed',
          'readOnly': true,
        },
      }),
    )));

    expect(find.text(_title), findsOneWidget);
    expect(find.textContaining('BLE connection failed'), findsOneWidget);
    expect(find.textContaining('-91 dBm'), findsOneWidget);
    expect(find.textContaining('Check the BMS is powered'), findsOneWidget);
    expect(find.byType(JKBMSRAlertBanner), findsOneWidget);
  });

  testWidgets('link up -> no banner at all', (tester) async {
    await tester.pumpWidget(_wrap(BmsLinkBanner(
      telemetry: _telemetry({
        'bmsLinkUp': true,
        'ble': {'state': 'connected', 'rssi': -60, 'lastError': ''},
      }),
    )));

    expect(find.text(_title), findsNothing);
    expect(find.byType(JKBMSRAlertBanner), findsNothing);
    expect(find.byType(SizedBox), findsWidgets); // only the shrink placeholder
  });

  testWidgets('bmsLinkUp absent -> treated as unknown, no banner', (tester) async {
    await tester.pumpWidget(_wrap(BmsLinkBanner(
      telemetry: _telemetry(const {'ble': {'state': 'disabled', 'rssi': -128}}),
    )));

    expect(find.text(_title), findsNothing);
    expect(find.byType(JKBMSRAlertBanner), findsNothing);
  });

  testWidgets('no telemetry -> no banner', (tester) async {
    await tester.pumpWidget(_wrap(const BmsLinkBanner(telemetry: null)));

    expect(find.text(_title), findsNothing);
    expect(find.byType(JKBMSRAlertBanner), findsNothing);
  });
}
