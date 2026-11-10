import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/features/alerts/pack_check.dart';
import 'package:jkbmsr_pro/features/battery/pack_status.dart';
import 'package:jkbmsr_pro/models/device.dart';
import 'package:jkbmsr_pro/models/telemetry.dart';

PackStatusInput _input({
  bool isOwner = true,
  String? ownerEmail,
  String? firmwareVersion = '0.9.10',
  String? latestFirmwareVersion = '0.9.10',
  bool updateAvailable = false,
  bool hasTelemetry = true,
  List<double> cellVoltages = const [3.300, 3.302, 3.304, 3.306],
  double? temperature1C = 22.0,
  double? temperature2C = 22.4,
  double? socPercent = 84,
  double? currentAmps = -12.0,
  double? fullCapacityAh = 100,
  bool isDischarging = true,
  bool? bmsLinkUp = true,
  int? secondsSinceLastTelemetry = 12,
  int? expectedIntervalSeconds = 60,
}) {
  return PackStatusInput(
    isOwner: isOwner,
    ownerEmail: ownerEmail,
    firmwareVersion: firmwareVersion,
    latestFirmwareVersion: latestFirmwareVersion,
    updateAvailable: updateAvailable,
    pack: PackCheckInput(
      deviceName: 'Garage pack',
      hasTelemetry: hasTelemetry,
      cellVoltages: hasTelemetry ? cellVoltages : const [],
      temperature1C: hasTelemetry ? temperature1C : 0,
      temperature2C: hasTelemetry ? temperature2C : 0,
      socPercent: hasTelemetry ? socPercent : null,
      currentAmps: hasTelemetry ? currentAmps : null,
      fullCapacityAh: hasTelemetry ? fullCapacityAh : null,
      isDischarging: isDischarging,
      bmsLinkUp: bmsLinkUp,
      secondsSinceLastTelemetry: secondsSinceLastTelemetry,
      expectedIntervalSeconds: expectedIntervalSeconds,
    ),
  );
}

PackStatusLine _line(PackStatusSummary summary, String label) {
  return summary.lines.firstWhere((line) => line.label == label);
}

Device _device({
  bool isOwner = true,
  String? ownerEmail,
  String? firmwareVersion = '0.9.10',
  String? latestFirmwareVersion = '0.9.10',
  bool updateAvailable = false,
  int? secondsSinceLastTelemetry = 12,
}) {
  return Device(
    id: 'gw-1',
    name: 'Garage pack',
    status: 'online',
    targetHardware: 'esp32-s3-16mb',
    otaChannel: 'stable',
    soc: 84,
    voltage: 53.2,
    current: -12,
    firmwareVersion: firmwareVersion,
    lastSeen: '2026-11-09 10:00:00',
    latestFirmwareVersion: latestFirmwareVersion,
    updateAvailable: updateAvailable,
    expectedIntervalSeconds: 60,
    secondsSinceLastTelemetry: secondsSinceLastTelemetry,
    isOwner: isOwner,
    ownerEmail: ownerEmail,
  );
}

Telemetry _telemetry({
  double voltage = 53.2,
  double soc = 84,
  bool? bmsLinkUp = true,
  List<CellVoltage>? cells,
}) {
  return Telemetry(
    voltage: voltage,
    current: -12,
    power: 638.4,
    soc: soc,
    temperature1: 22.0,
    temperature2: 22.4,
    cells: cells ??
        [
          CellVoltage(cell: 1, voltage: 3.300),
          CellVoltage(cell: 2, voltage: 3.302),
          CellVoltage(cell: 3, voltage: 3.304),
          CellVoltage(cell: 4, voltage: 3.306),
        ],
    bms: BmsExtras.fromJson({
      'fullCapacityAh': 100.0,
      'charging': false,
      'discharging': true,
    }),
    diagnostics: {'bmsLinkUp': bmsLinkUp},
  );
}

void main() {
  group('buildPackStatus', () {
    test('a fully set-up gateway ticks every line and reads clear', () {
      final summary = buildPackStatus(_input());

      expect(summary.lines, hasLength(4));

      final claimed = _line(summary, 'Gateway claimed');
      expect(claimed.mark, PackStatusMark.done);
      expect(claimed.detail, 'Claimed by this account');

      final reporting = _line(summary, 'Reporting telemetry');
      expect(reporting.mark, PackStatusMark.done);
      expect(reporting.detail, 'Last report 12s ago');

      final link = _line(summary, 'Battery link');
      expect(link.mark, PackStatusMark.done);

      final firmware = _line(summary, 'Firmware up to date');
      expect(firmware.mark, PackStatusMark.done);
      expect(firmware.detail, 'Up to date: 0.9.10');

      expect(summary.health.tone, PackStatusHealthTone.clear);
      expect(
        summary.health.sentence,
        'The readings that could be checked look normal.',
      );
      expect(summary.health.findingCount, 0);
    });

    test('a gateway that has never reported is not ticked', () {
      final summary = buildPackStatus(_input(
        hasTelemetry: false,
        bmsLinkUp: null,
        secondsSinceLastTelemetry: null,
      ));

      final reporting = _line(summary, 'Reporting telemetry');
      expect(reporting.mark, PackStatusMark.pending);
      expect(reporting.detail, 'Not reported yet');

      final link = _line(summary, 'Battery link');
      expect(link.mark, PackStatusMark.unknown);

      // A known firmware version is still a known fact, so only the two
      // reporting lines change.
      expect(_line(summary, 'Gateway claimed').mark, PackStatusMark.done);
      expect(_line(summary, 'Firmware up to date').mark, PackStatusMark.done);

      expect(summary.health.tone, PackStatusHealthTone.unknown);
      expect(
        summary.health.sentence,
        'Not enough data to check the pack yet.',
      );
    });

    test('an available update reads as a pending line, with its version', () {
      final summary = buildPackStatus(_input(
        firmwareVersion: '0.9.9',
        latestFirmwareVersion: '0.9.10',
        updateAvailable: true,
      ));

      final firmware = _line(summary, 'Firmware up to date');
      expect(firmware.mark, PackStatusMark.pending);
      expect(firmware.detail, 'Update available: 0.9.10');
    });

    test('an update with no published version still reads as pending', () {
      final summary = buildPackStatus(_input(
        firmwareVersion: '0.9.9',
        latestFirmwareVersion: null,
        updateAvailable: true,
      ));

      final firmware = _line(summary, 'Firmware up to date');
      expect(firmware.mark, PackStatusMark.pending);
      expect(firmware.detail, 'Update available');
    });

    test('missing firmware data is unknown, never a tick', () {
      final noInstalled = buildPackStatus(_input(
        firmwareVersion: null,
        latestFirmwareVersion: '0.9.10',
      ));

      final installed = _line(noInstalled, 'Firmware up to date');
      expect(installed.mark, PackStatusMark.unknown);
      expect(installed.detail, 'The installed version was not reported');

      final noLatest = buildPackStatus(_input(
        firmwareVersion: '0.9.10',
        latestFirmwareVersion: null,
      ));

      final latest = _line(noLatest, 'Firmware up to date');
      expect(latest.mark, PackStatusMark.unknown);
      expect(latest.detail, 'Installed 0.9.10 · latest version unknown');
    });

    test('a gateway that checked in without readings is not ticked', () {
      final summary = buildPackStatus(_input(
        hasTelemetry: false,
        secondsSinceLastTelemetry: 7500,
      ));

      final reporting = _line(summary, 'Reporting telemetry');
      expect(reporting.mark, PackStatusMark.pending);
      expect(reporting.detail, 'Checked in 2h 5m ago with no battery readings');
    });

    test('a shared gateway still says who claimed it', () {
      final summary = buildPackStatus(_input(
        isOwner: false,
        ownerEmail: 'owner@example.com',
      ));

      final claimed = _line(summary, 'Gateway claimed');
      expect(claimed.mark, PackStatusMark.done);
      expect(claimed.detail, 'Claimed by owner@example.com');
    });

    test('a down battery link is pending and produces a finding', () {
      final summary = buildPackStatus(_input(bmsLinkUp: false));

      final link = _line(summary, 'Battery link');
      expect(link.mark, PackStatusMark.pending);

      expect(summary.health.tone, PackStatusHealthTone.attention);
      expect(summary.health.sentence, '1 thing to check');
      expect(summary.health.findingCount, 1);
    });

    test('a critical pack finding keeps the count and the critical tone', () {
      final summary = buildPackStatus(_input(
        cellVoltages: const [2.450, 3.300, 3.310, 3.320],
      ));

      expect(summary.health.tone, PackStatusHealthTone.critical);
      expect(summary.health.sentence, '1 thing to check');
      expect(summary.health.findingCount, 1);
    });

    test('several findings are counted in the sentence', () {
      final summary = buildPackStatus(_input(
        cellVoltages: const [3.200, 3.400, 3.210, 3.220],
        temperature1C: 55.0,
        temperature2C: 22.0,
      ));

      expect(summary.health.sentence, '3 things to check');
      expect(summary.health.findingCount, 3);
    });

    test('findings the Alerts card does not render are still counted', () {
      final summary = buildPackStatus(_input(
        cellVoltages: const [3.200, 3.400, 3.210, 3.220],
        temperature1C: 55.0,
        temperature2C: 22.0,
        socPercent: 5,
        currentAmps: -60.0,
      ));

      // The pack check renders at most three findings; the summary counts
      // every finding so its sentence cannot understate the work.
      expect(summary.health.findingCount, 4);
      expect(summary.health.sentence, '4 things to check');
      expect(summary.health.tone, PackStatusHealthTone.critical);
    });
  });

  group('packStatusInputFor', () {
    test('reduces a known device and telemetry to the same summary', () {
      final summary = buildPackStatus(
        packStatusInputFor(_device(), _telemetry()),
      );

      expect(_line(summary, 'Reporting telemetry').mark, PackStatusMark.done);
      expect(_line(summary, 'Battery link').mark, PackStatusMark.done);
      expect(
          _line(summary, 'Firmware up to date').detail, 'Up to date: 0.9.10');
      expect(summary.health.tone, PackStatusHealthTone.clear);
    });

    test('zero readings mean no telemetry, not a flat battery', () {
      final summary = buildPackStatus(
        packStatusInputFor(
          _device(secondsSinceLastTelemetry: null),
          _telemetry(voltage: 0, soc: 0, bmsLinkUp: null),
        ),
      );

      expect(_line(summary, 'Reporting telemetry').detail, 'Not reported yet');
      expect(_line(summary, 'Battery link').mark, PackStatusMark.unknown);
      expect(summary.health.tone, PackStatusHealthTone.unknown);
    });

    test('a missing telemetry object is not read as healthy', () {
      final summary = buildPackStatus(
        packStatusInputFor(
          _device(secondsSinceLastTelemetry: null),
          null,
        ),
      );

      expect(
          _line(summary, 'Reporting telemetry').mark, PackStatusMark.pending);
      expect(_line(summary, 'Battery link').mark, PackStatusMark.unknown);
      expect(summary.health.tone, PackStatusHealthTone.unknown);
    });

    test('a shared device keeps its owner in the claimed line', () {
      final summary = buildPackStatus(
        packStatusInputFor(
          _device(isOwner: false, ownerEmail: 'owner@example.com'),
          _telemetry(),
        ),
      );

      expect(
        _line(summary, 'Gateway claimed').detail,
        'Claimed by owner@example.com',
      );
    });
  });
}
