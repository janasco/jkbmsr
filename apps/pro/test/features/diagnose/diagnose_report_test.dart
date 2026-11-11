// The diagnosis rules: no thresholds of their own, and never "clear" when a
// value was missing.

import 'package:flutter_test/flutter_test.dart';

import 'package:jkbmsr_pro/features/alerts/pack_check.dart';
import 'package:jkbmsr_pro/features/diagnose/diagnose_report.dart';
import 'package:jkbmsr_pro/models/telemetry.dart';

BmsLinkDiagnostics _link({bool? up, int rssi = -128, String error = ''}) {
  return BmsLinkDiagnostics(
    bmsLinkUp: up,
    bleState: up == null ? '' : (up ? 'connected' : 'connection_failed'),
    lastError: error,
    rssi: rssi,
    bytesReceived: up == true ? 4096 : 0,
  );
}

PackCheckInput _pack({
  bool hasTelemetry = true,
  bool? linkUp = true,
  double cell = 3.300,
  List<double>? cells,
}) {
  final voltages = cells ?? List<double>.filled(16, cell);
  return PackCheckInput(
    deviceName: 'Test gateway',
    hasTelemetry: hasTelemetry,
    cellVoltages: hasTelemetry ? voltages : const [],
    temperature1C: hasTelemetry ? 25 : null,
    temperature2C: hasTelemetry ? 26 : null,
    socPercent: hasTelemetry ? 80 : null,
    currentAmps: hasTelemetry ? 0 : null,
    fullCapacityAh: hasTelemetry ? 280 : null,
    isCharging: false,
    isDischarging: false,
    bmsLinkUp: linkUp,
    secondsSinceLastTelemetry: hasTelemetry ? 30 : null,
    expectedIntervalSeconds: 3600,
  );
}

void main() {
  test('a healthy pack with a connected link reads clear', () {
    final report = buildDiagnoseReport(
      pack: _pack(),
      gatewayOnline: true,
      link: _link(up: true, rssi: -60),
    );

    expect(report.tone, DiagnoseTone.clear);
    expect(report.headline, contains('Nothing looks wrong'));
    expect(report.checks.every((c) => c.tone != DiagnoseTone.critical), isTrue);
  });

  test('an unreported battery link is unknown, never clear', () {
    final report = buildDiagnoseReport(
      pack: _pack(linkUp: null),
      gatewayOnline: true,
      link: _link(up: null),
    );

    // The pack itself is fine, and the report still must not claim the whole
    // picture is fine: one of its two questions was never answered.
    expect(report.tone, DiagnoseTone.unknown);
    expect(report.headline, contains('could not be checked'));
    final link = report.checks.firstWhere((c) => c.title == 'Battery link');
    expect(link.tone, DiagnoseTone.unknown);
    expect(link.detail, contains('missing value'));
  });

  test('a down battery link is attention with a next step', () {
    final report = buildDiagnoseReport(
      pack: _pack(linkUp: false),
      gatewayOnline: true,
      link: _link(up: false, error: 'no response'),
    );

    final link = report.checks.firstWhere((c) => c.title == 'Battery link');
    expect(link.tone, DiagnoseTone.attention);
    expect(link.detail, contains('not connected to the battery'));
    expect(link.detail, contains('no response'));
    expect(link.nextStep, isNotNull);
    expect(report.tone, DiagnoseTone.attention);
  });

  test('a weak signal on a working link suggests moving the gateway', () {
    final report = buildDiagnoseReport(
      pack: _pack(),
      gatewayOnline: true,
      link: _link(up: true, rssi: -92),
    );

    final link = report.checks.firstWhere((c) => c.title == 'Battery link');
    expect(link.tone, DiagnoseTone.clear);
    expect(link.nextStep, contains('closer'));
  });

  test('a gateway that stopped reporting says so', () {
    final report = buildDiagnoseReport(
      pack: _pack(),
      gatewayOnline: false,
      link: _link(up: true, rssi: -60),
    );

    final gateway =
        report.checks.firstWhere((c) => c.title == 'Gateway connection');
    expect(gateway.tone, DiagnoseTone.attention);
    expect(report.tone, DiagnoseTone.attention);
  });

  test('no readings is unknown when the gateway is still reporting', () {
    final report = buildDiagnoseReport(
      pack: _pack(hasTelemetry: false),
      gatewayOnline: true,
      link: _link(up: null),
    );

    expect(report.hasData, isFalse);
    expect(report.tone, DiagnoseTone.unknown);
    expect(report.headline, isNotEmpty);
    expect(report.facts, isEmpty);
  });

  test('no readings and a silent gateway is attention, because there is a fix', () {
    // Both are true. The offline gateway is the actionable one, so that is the
    // headline; "no readings" alone would leave the owner with nothing to do.
    final report = buildDiagnoseReport(
      pack: _pack(hasTelemetry: false),
      gatewayOnline: false,
      link: _link(up: null),
    );

    expect(report.hasData, isFalse);
    expect(report.tone, DiagnoseTone.attention);
  });

  test('the facts shown are the ones the pack check derived its verdict from', () {
    final report = buildDiagnoseReport(
      pack: _pack(cells: [
        for (var i = 0; i < 16; i++) i == 3 ? 3.28 : 3.31,
      ]),
      gatewayOnline: true,
      link: _link(up: true, rssi: -60),
    );

    // Whatever the pack check decided, the screen shows its facts rather than
    // re-deriving them, so the two surfaces cannot disagree.
    final expected = evaluatePackCheck([_pack(cells: [
      for (var i = 0; i < 16; i++) i == 3 ? 3.28 : 3.31,
    ])]).facts;
    expect(report.facts, expected);
  });
}
