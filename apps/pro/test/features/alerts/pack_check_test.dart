import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/features/alerts/pack_check.dart';

PackCheckInput _pack({
  String deviceName = 'Garage pack',
  bool hasTelemetry = true,
  List<double> cellVoltages = const [3.300, 3.302, 3.304, 3.306],
  double? temperature1C = 22.0,
  double? temperature2C = 22.4,
  double? socPercent = 84,
  double? currentAmps = -12.0,
  double? fullCapacityAh = 100,
  bool isCharging = false,
  bool isDischarging = true,
  bool? bmsLinkUp = true,
  int? secondsSinceLastTelemetry = 12,
  int? expectedIntervalSeconds = 60,
}) {
  return PackCheckInput(
    deviceName: deviceName,
    hasTelemetry: hasTelemetry,
    cellVoltages: cellVoltages,
    temperature1C: temperature1C,
    temperature2C: temperature2C,
    socPercent: socPercent,
    currentAmps: currentAmps,
    fullCapacityAh: fullCapacityAh,
    isCharging: isCharging,
    isDischarging: isDischarging,
    bmsLinkUp: bmsLinkUp,
    secondsSinceLastTelemetry: secondsSinceLastTelemetry,
    expectedIntervalSeconds: expectedIntervalSeconds,
  );
}

void main() {
  group('evaluatePackCheck', () {
    test('an imbalanced pack produces a finding with the spread', () {
      final report = evaluatePackCheck([
        _pack(cellVoltages: const [3.300, 3.355, 3.310, 3.300]),
      ]);

      expect(report.verdict, PackCheckVerdict.findings);
      expect(report.findings, hasLength(1));
      expect(report.findings.single.severity, PackCheckSeverity.attention);
      expect(
        report.findings.single.title,
        'Cell 2 is 55 mV above cell 1',
      );
      expect(report.findings.single.detail, contains('spread 55 mV'));
    });

    test('a healthy pack produces no findings and carries its numbers', () {
      final report = evaluatePackCheck([_pack()]);

      expect(report.verdict, PackCheckVerdict.clear);
      expect(report.findings, isEmpty);
      expect(report.facts, hasLength(1));
      expect(report.facts.single, contains('4 cells'));
      expect(report.facts.single, contains('6 mV spread'));
      expect(report.facts.single, contains('22.4 °C'));
      expect(report.facts.single, contains('84% charge'));
      expect(report.facts.single, startsWith('Garage pack'));
    });

    test('missing telemetry says so instead of guessing', () {
      final report = evaluatePackCheck([
        _pack(
          hasTelemetry: false,
          cellVoltages: const [],
          temperature1C: 0,
          temperature2C: 0,
          socPercent: 0,
          currentAmps: 0,
          fullCapacityAh: 0,
          secondsSinceLastTelemetry: null,
        ),
      ]);

      expect(report.verdict, PackCheckVerdict.insufficientData);
      expect(report.findings, isEmpty);
      expect(report.noDataReason, contains('has not reported telemetry yet'));
    });

    test('telemetry without cell, temperature or charge values is not enough',
        () {
      final report = evaluatePackCheck([
        _pack(
          cellVoltages: const [],
          temperature1C: 0,
          temperature2C: 0,
          socPercent: null,
          currentAmps: null,
          fullCapacityAh: null,
        ),
      ]);

      expect(report.verdict, PackCheckVerdict.insufficientData);
      expect(
        report.noDataReason,
        contains('did not report cell, temperature or charge values'),
      );
    });

    test('a cell at the 2.5 V cutoff is critical', () {
      final report = evaluatePackCheck([
        _pack(cellVoltages: const [2.450, 3.300]),
      ]);

      expect(report.verdict, PackCheckVerdict.findings);
      expect(report.findings.single.severity, PackCheckSeverity.critical);
      expect(report.findings.single.title, contains('reported at 2.45 V'));
      expect(report.findings.single.detail, contains('2.5 V is the conventional'));
    });

    test('50 °C is critical, matching the dashboard temperature tiles', () {
      final report = evaluatePackCheck([
        _pack(temperature1C: 50.2, temperature2C: 49.8),
      ]);

      expect(report.verdict, PackCheckVerdict.findings);
      expect(report.findings.single.severity, PackCheckSeverity.critical);
      expect(report.findings.single.title, contains('50.2 °C'));
    });

    test('a 10 °C gap between the two sensors is reported', () {
      final report = evaluatePackCheck([
        _pack(temperature1C: 35.0, temperature2C: 24.0),
      ]);

      expect(report.verdict, PackCheckVerdict.findings);
      expect(report.findings, hasLength(1));
      expect(report.findings.single.severity, PackCheckSeverity.attention);
      expect(report.findings.single.title, contains('11.0 °C apart'));
      expect(report.findings.single.detail, contains('Sensor 1: 35.0 °C'));
      expect(report.findings.single.detail, contains('Sensor 2: 24.0 °C'));
    });

    test('a gateway more than three intervals late is called stopped', () {
      final report = evaluatePackCheck([
        _pack(secondsSinceLastTelemetry: 181, expectedIntervalSeconds: 60),
      ]);

      expect(report.verdict, PackCheckVerdict.findings);
      expect(report.findings.single.title, 'Gateway has stopped reporting');
      expect(report.findings.single.detail, contains('3m ago'));
      expect(report.findings.single.detail, contains('every 1m'));
    });

    test('exactly three intervals late is still within tolerance', () {
      final report = evaluatePackCheck([
        _pack(secondsSinceLastTelemetry: 180, expectedIntervalSeconds: 60),
      ]);

      expect(report.verdict, PackCheckVerdict.clear);
      expect(report.findings, isEmpty);
    });

    test('a near-empty pack under a heavy discharge is reported', () {
      final report = evaluatePackCheck([
        _pack(socPercent: 8, currentAmps: -60, fullCapacityAh: 100),
      ]);

      expect(report.verdict, PackCheckVerdict.findings);
      expect(report.findings.single.title, contains('8%'));
      expect(report.findings.single.title, contains('discharged at 60.0 A'));
      expect(report.findings.single.detail, contains('0.6 C'));
    });

    test('a near-empty pack under a light discharge produces no finding', () {
      final report = evaluatePackCheck([
        _pack(socPercent: 8, currentAmps: -40, fullCapacityAh: 100),
      ]);

      expect(report.verdict, PackCheckVerdict.clear);
      expect(report.findings, isEmpty);
    });

    test('a near-full pack under a heavy charge is reported', () {
      final report = evaluatePackCheck([
        _pack(
          socPercent: 97,
          currentAmps: 60,
          fullCapacityAh: 100,
          isCharging: true,
          isDischarging: false,
        ),
      ]);

      expect(report.verdict, PackCheckVerdict.findings);
      expect(report.findings.single.title, contains('97%'));
      expect(report.findings.single.title, contains('charged at 60.0 A'));
    });

    test('a down BMS link skips the numeric checks and says why', () {
      final report = evaluatePackCheck([
        _pack(
          bmsLinkUp: false,
          cellVoltages: const [3.300, 3.500],
        ),
      ]);

      expect(report.verdict, PackCheckVerdict.findings);
      expect(report.findings, hasLength(1));
      expect(report.findings.single.title, 'No live readings from the battery');
      expect(
        report.findings.single.detail,
        contains('cell, temperature and charge checks were skipped'),
      );
    });

    test('critical findings sort ahead of attention findings', () {
      final report = evaluatePackCheck([
        _pack(deviceName: 'Attic pack', cellVoltages: const [3.300, 3.355]),
        _pack(deviceName: 'Garage pack', temperature1C: 55.0, temperature2C: 55.0),
      ]);

      expect(report.verdict, PackCheckVerdict.findings);
      expect(report.findings.first.deviceName, 'Garage pack');
      expect(report.findings.first.severity, PackCheckSeverity.critical);
    });

    test('more than three findings are capped and counted', () {
      final report = evaluatePackCheck([
        for (var i = 0; i < 4; i++)
          _pack(deviceName: 'Pack $i', temperature1C: 55.0, temperature2C: 55.0),
      ]);

      expect(report.verdict, PackCheckVerdict.findings);
      expect(report.findings, hasLength(3));
      expect(report.hiddenFindings, 1);
    });

    test('an empty gateway list is not enough data', () {
      final report = evaluatePackCheck(const []);

      expect(report.verdict, PackCheckVerdict.insufficientData);
      expect(report.noDataReason, contains('No gateway telemetry'));
    });

    test('a partial read is disclosed rather than hidden', () {
      final report = evaluatePackCheck(
        [_pack()],
        coverageNote: '1 of 2 gateways could not be read.',
      );

      expect(report.verdict, PackCheckVerdict.clear);
      expect(report.coverageNote, '1 of 2 gateways could not be read.');
    });

    test('a gateway with no readings is counted beside a clear pack', () {
      final report = evaluatePackCheck([
        _pack(deviceName: 'Garage pack'),
        _pack(
          deviceName: 'Attic pack',
          hasTelemetry: false,
          cellVoltages: const [],
          temperature1C: 0,
          temperature2C: 0,
          socPercent: null,
          currentAmps: null,
          fullCapacityAh: null,
          secondsSinceLastTelemetry: null,
        ),
      ]);

      expect(report.verdict, PackCheckVerdict.clear);
      expect(
        report.coverageNote,
        contains('1 of 2 gateways had no readings to check'),
      );
    });
  });
}
