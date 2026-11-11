// The diagnosis screen: the named wait, the three states that are not a
// report, and the report itself.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jkbmsr_pro/features/diagnose/diagnose_screen.dart';
import 'package:jkbmsr_pro/features/diagnose/diagnose_source.dart';
import 'package:jkbmsr_pro/models/device.dart';
import 'package:jkbmsr_pro/models/telemetry.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

Device _device({String status = 'online', String id = 'gw-1'}) => Device(
      id: id,
      name: 'Garage pack',
      status: status,
      targetHardware: 'esp32-s3-16mb',
      otaChannel: 'stable',
      soc: 80,
      voltage: 52.8,
      current: 0,
      lastSeen: '2026-11-11T09:00:00Z',
      updateAvailable: false,
      secondsSinceLastTelemetry: 30,
      expectedIntervalSeconds: 3600,
    );

BmsExtras _bms() => BmsExtras(
      mosfetTemperature: 26,
      minCellVoltage: 3.30,
      maxCellVoltage: 3.30,
      avgCellVoltage: 3.30,
      deltaCellVoltage: 0.001,
      minVoltageCell: 1,
      maxVoltageCell: 1,
      cycleCount: 12,
      cycleCapacityAh: 100,
      fullCapacityAh: 280,
      remainingCapacityAh: 224,
      stateOfHealth: 98,
      balancingCurrent: 0,
      balancing: false,
      charging: false,
      discharging: false,
      errorsBitmask: 0,
    );

Telemetry _telemetry() => Telemetry(
      voltage: 52.8,
      current: 0,
      power: 0,
      soc: 80,
      temperature1: 25,
      temperature2: 26,
      cells: [for (var i = 1; i <= 16; i++) CellVoltage(cell: i, voltage: 3.30)],
      bms: _bms(),
      diagnostics: const {
        'bmsLinkUp': true,
        'ble': {'state': 'connected', 'rssi': -60},
      },
    );

Widget _host(Widget child) => MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: child,
    );

void main() {
  testWidgets('the wait says what it is waiting for', (tester) async {
    final source = FakeDiagnoseSource(deviceList: [_device()], telemetry: _telemetry());
    await tester.pumpWidget(_host(DiagnoseScreen(source: source)));

    // First frame, before the futures resolve.
    expect(find.text('Reading the latest values'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Reading the latest values'), findsNothing);
  });

  testWidgets('a report names the finding and the measurement behind it',
      (tester) async {
    final source = FakeDiagnoseSource(deviceList: [_device()], telemetry: _telemetry());
    await tester.pumpWidget(_host(DiagnoseScreen(source: source)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing looks wrong'), findsOneWidget);
    expect(find.text('Battery link'), findsOneWidget);
    expect(find.textContaining('-60 dBm'), findsOneWidget);
    // Facts come from the pack check rather than being re-derived here.
    expect(find.text('What these were read from'), findsOneWidget);
  });

  testWidgets('a failed read offers the action that fixes it', (tester) async {
    final source = FakeDiagnoseSource(error: Exception('network'));
    await tester.pumpWidget(_host(DiagnoseScreen(source: source)));
    await tester.pumpAndSettle();

    expect(find.text('Could not read this gateway'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('no gateway is a state, not an error', (tester) async {
    final source = FakeDiagnoseSource(deviceList: const []);
    await tester.pumpWidget(_host(DiagnoseScreen(source: source)));
    await tester.pumpAndSettle();

    expect(find.text('No gateway yet'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('more than one gateway asks before diagnosing', (tester) async {
    final source = FakeDiagnoseSource(
      deviceList: [_device(), _device(id: 'gw-2')],
      telemetry: _telemetry(),
    );
    await tester.pumpWidget(_host(DiagnoseScreen(source: source)));
    await tester.pumpAndSettle();

    // Diagnosing the wrong pack is worse than one extra tap.
    expect(find.text('Which gateway?'), findsOneWidget);
    expect(source.telemetryCalls, 0);

    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.text('Battery link'), findsOneWidget);
  });
}
