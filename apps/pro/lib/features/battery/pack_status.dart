/// Pure decision logic for the dashboard's compact "Pack status" summary.
///
/// The summary is a setup checklist plus one health sentence. Every line is a
/// fact the app already holds; a missing value is rendered as unknown rather
/// than as a passing line, and nothing here adjusts the thresholds owned by
/// [evaluatePackCheck].
library;

import '../alerts/pack_check.dart';
import '../../models/device.dart';
import '../../models/telemetry.dart';

/// How a checklist line should be read.
enum PackStatusMark {
  /// The gateway has this working, and the data says so.
  done,

  /// The gateway does not have this yet (never reported, update pending, or a
  /// reported link that is down).
  pending,

  /// The app cannot tell, because the value was not reported.
  unknown,
}

/// One checklist line with its state.
class PackStatusLine {
  const PackStatusLine({
    required this.label,
    required this.detail,
    required this.mark,
  });

  final String label;
  final String detail;
  final PackStatusMark mark;
}

/// The tone of the health sentence, so the widget can colour it without
/// re-deriving the pack-check verdict.
enum PackStatusHealthTone { clear, attention, critical, unknown }

/// The one-sentence health summary shown under the checklist.
class PackStatusHealth {
  const PackStatusHealth({
    required this.sentence,
    required this.tone,
    this.findingCount = 0,
  });

  final String sentence;
  final PackStatusHealthTone tone;

  /// Number of findings, including any the Alerts card did not render. Zero
  /// when there is nothing to check or everything checked came back clear.
  final int findingCount;
}

/// Everything the dashboard can say about this gateway without guessing.
class PackStatusSummary {
  const PackStatusSummary({required this.lines, required this.health});

  final List<PackStatusLine> lines;
  final PackStatusHealth health;

  /// True when at least one line is not `done`, or the pack check has something
  /// to report. The dashboard shows the card only in that case: a permanent
  /// four-line checklist pushes the state of charge below the fold for every
  /// owner who has nothing left to set up, and what the card is *for* is what is
  /// still outstanding.
  bool get hasPending =>
      lines.any((line) => line.mark != PackStatusMark.done) ||
      health.tone == PackStatusHealthTone.attention ||
      health.tone == PackStatusHealthTone.critical;
}

/// Plain input for [buildPackStatus].
///
/// [pack] is the same value the Alerts screen feeds to [evaluatePackCheck], so
/// the two surfaces cannot disagree about the pack's health. The remaining
/// fields are the setup facts the checklist needs.
class PackStatusInput {
  const PackStatusInput({
    required this.pack,
    required this.isOwner,
    this.ownerEmail,
    this.firmwareVersion,
    this.latestFirmwareVersion,
    required this.updateAvailable,
  });

  final PackCheckInput pack;
  final bool isOwner;
  final String? ownerEmail;
  final String? firmwareVersion;
  final String? latestFirmwareVersion;
  final bool updateAvailable;
}

/// Reduces the device and its telemetry to the values [buildPackStatus] reads.
///
/// This mirrors the reduction the Alerts screen performs: the API sends
/// voltage and SOC as zero when no telemetry row exists, and a real connected
/// pack does not sit at exactly 0 V.
PackStatusInput packStatusInputFor(Device device, Telemetry? telemetry) {
  final hasTelemetry =
      telemetry != null && (telemetry.voltage > 0.5 || telemetry.soc > 0);
  final link = telemetry?.linkDiagnostics;

  return PackStatusInput(
    isOwner: device.isOwner,
    ownerEmail: device.ownerEmail,
    firmwareVersion: device.firmwareVersion,
    latestFirmwareVersion: device.latestFirmwareVersion,
    updateAvailable: device.updateAvailable,
    pack: PackCheckInput(
      deviceName: device.name,
      hasTelemetry: hasTelemetry,
      cellVoltages: hasTelemetry
          ? [for (final cell in telemetry.cells) cell.voltage]
          : const [],
      temperature1C: telemetry?.temperature1,
      temperature2C: telemetry?.temperature2,
      socPercent: hasTelemetry ? telemetry.soc : null,
      currentAmps: hasTelemetry ? telemetry.current : null,
      fullCapacityAh: (telemetry?.bms.fullCapacityAh ?? 0) > 0
          ? telemetry!.bms.fullCapacityAh
          : null,
      isCharging: telemetry?.bms.charging ?? false,
      isDischarging: telemetry?.bms.discharging ?? false,
      bmsLinkUp: link?.bmsLinkUp,
      secondsSinceLastTelemetry: device.secondsSinceLastTelemetry,
      expectedIntervalSeconds: device.expectedIntervalSeconds,
    ),
  );
}

/// Builds the checklist and health sentence from values the app already has.
PackStatusSummary buildPackStatus(PackStatusInput input) {
  return PackStatusSummary(
    lines: [
      _claimedLine(input),
      _reportingLine(input.pack),
      _batteryLinkLine(input.pack),
      _firmwareLine(input),
    ],
    health: _health(input.pack),
  );
}

PackStatusLine _claimedLine(PackStatusInput input) {
  if (input.isOwner) {
    return const PackStatusLine(
      label: 'Gateway claimed',
      detail: 'Claimed by this account',
      mark: PackStatusMark.done,
    );
  }

  final owner = input.ownerEmail;
  return PackStatusLine(
    label: 'Gateway claimed',
    detail: owner == null || owner.isEmpty
        ? 'Claimed by another account'
        : 'Claimed by $owner',
    mark: PackStatusMark.done,
  );
}

PackStatusLine _reportingLine(PackCheckInput pack) {
  if (pack.hasTelemetry) {
    final since = pack.secondsSinceLastTelemetry;
    return PackStatusLine(
      label: 'Reporting telemetry',
      detail: since == null
          ? 'Readings received'
          : 'Last report ${_formatAge(since)} ago',
      mark: PackStatusMark.done,
    );
  }

  final since = pack.secondsSinceLastTelemetry;
  if (since == null) {
    return const PackStatusLine(
      label: 'Reporting telemetry',
      detail: 'Not reported yet',
      mark: PackStatusMark.pending,
    );
  }

  return PackStatusLine(
    label: 'Reporting telemetry',
    detail: 'Checked in ${_formatAge(since)} ago with no battery readings',
    mark: PackStatusMark.pending,
  );
}

PackStatusLine _batteryLinkLine(PackCheckInput pack) {
  final linkUp = pack.bmsLinkUp;
  if (linkUp == null) {
    return const PackStatusLine(
      label: 'Battery link',
      detail: 'The gateway did not report its link to the battery',
      mark: PackStatusMark.unknown,
    );
  }
  if (!linkUp) {
    return const PackStatusLine(
      label: 'Battery link',
      detail: 'The gateway reports no link to the battery',
      mark: PackStatusMark.pending,
    );
  }
  return const PackStatusLine(
    label: 'Battery link',
    detail: 'The gateway has a live link to the battery',
    mark: PackStatusMark.done,
  );
}

PackStatusLine _firmwareLine(PackStatusInput input) {
  if (input.updateAvailable) {
    final latest = input.latestFirmwareVersion;
    return PackStatusLine(
      label: 'Firmware up to date',
      detail: latest == null || latest.isEmpty
          ? 'Update available'
          : 'Update available — $latest',
      mark: PackStatusMark.pending,
    );
  }

  final installed = input.firmwareVersion;
  if (installed == null || installed.isEmpty) {
    return const PackStatusLine(
      label: 'Firmware up to date',
      detail: 'The installed version was not reported',
      mark: PackStatusMark.unknown,
    );
  }

  final latest = input.latestFirmwareVersion;
  if (latest == null || latest.isEmpty) {
    return PackStatusLine(
      label: 'Firmware up to date',
      detail: 'Installed $installed · latest version unknown',
      mark: PackStatusMark.unknown,
    );
  }

  return PackStatusLine(
    label: 'Firmware up to date',
    detail: 'Up to date — $installed',
    mark: PackStatusMark.done,
  );
}

PackStatusHealth _health(PackCheckInput pack) {
  final report = evaluatePackCheck([pack]);

  switch (report.verdict) {
    case PackCheckVerdict.clear:
      return const PackStatusHealth(
        sentence: 'The readings that could be checked look normal.',
        tone: PackStatusHealthTone.clear,
      );
    case PackCheckVerdict.findings:
      final count = report.findings.length + report.hiddenFindings;
      final hasCritical = report.findings
          .any((finding) => finding.severity == PackCheckSeverity.critical);
      return PackStatusHealth(
        sentence: '$count ${count == 1 ? 'thing' : 'things'} to check',
        tone: hasCritical
            ? PackStatusHealthTone.critical
            : PackStatusHealthTone.attention,
        findingCount: count,
      );
    case PackCheckVerdict.insufficientData:
      return const PackStatusHealth(
        sentence: 'Not enough data to check the pack yet.',
        tone: PackStatusHealthTone.unknown,
      );
  }
}

String _formatAge(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  if (hours < 48) {
    final remainder = minutes % 60;
    return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
  }
  return '${hours ~/ 24}d';
}
