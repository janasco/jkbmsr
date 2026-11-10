/// Pure decision logic for the Alerts screen's "Pack check" card.
///
/// The card answers "what do these numbers mean?" and shows the numbers that
/// justify each statement. Everything is derived from values the app already
/// holds; nothing infers a cause the telemetry cannot support. When a check
/// cannot be computed from the data present, the report says so instead of
/// guessing.
library;

/// The overall state of a pack check.
enum PackCheckVerdict {
  /// No check could be run: the telemetry did not carry the values it needs.
  insufficientData,

  /// Every check that could run found nothing unusual.
  clear,

  /// At least one check produced a finding.
  findings,
}

/// How strongly a finding should be read. [critical] is reserved for a value
/// the app already renders as critical elsewhere; everything else is
/// [attention].
enum PackCheckSeverity { attention, critical }

/// One plain-language finding, with the numbers folded into [detail].
class PackCheckFinding {
  const PackCheckFinding({
    required this.deviceName,
    required this.title,
    required this.detail,
    required this.severity,
  });

  final String deviceName;
  final String title;
  final String detail;
  final PackCheckSeverity severity;
}

/// The result of checking one or more gateways.
class PackCheckReport {
  const PackCheckReport({
    required this.verdict,
    this.findings = const [],
    this.facts = const [],
    this.noDataReason,
    this.coverageNote,
    this.hiddenFindings = 0,
  });

  const PackCheckReport.noData(String reason, {this.coverageNote})
      : verdict = PackCheckVerdict.insufficientData,
        findings = const [],
        facts = const [],
        noDataReason = reason,
        hiddenFindings = 0;

  final PackCheckVerdict verdict;

  /// At most three findings, critical first. See [hiddenFindings] for any
  /// others that were deliberately not rendered.
  final List<PackCheckFinding> findings;

  /// One line per pack whose checks came back clear, e.g.
  /// "Garage pack — 16 cells · 8 mV spread · 84% charge".
  final List<String> facts;

  final String? noDataReason;

  /// Set when some gateways could not be read, so the card never implies it
  /// checked more packs than it did.
  final String? coverageNote;

  final int hiddenFindings;
}

/// Plain values for one gateway's latest telemetry.
///
/// Optional fields are nullable so "the payload did not say" stays distinct
/// from a real zero. The caller is responsible for passing `null` where the
/// API omitted a value; [hasTelemetry] is the same no-data signal the battery
/// dashboard uses (`voltage > 0.5 || soc > 0`).
class PackCheckInput {
  const PackCheckInput({
    required this.deviceName,
    required this.hasTelemetry,
    this.cellVoltages = const [],
    this.temperature1C,
    this.temperature2C,
    this.socPercent,
    this.currentAmps,
    this.fullCapacityAh,
    this.isCharging = false,
    this.isDischarging = false,
    this.bmsLinkUp,
    this.secondsSinceLastTelemetry,
    this.expectedIntervalSeconds,
  });

  final String deviceName;
  final bool hasTelemetry;
  final List<double> cellVoltages;
  final double? temperature1C;
  final double? temperature2C;
  final double? socPercent;
  final double? currentAmps;
  final double? fullCapacityAh;
  final bool isCharging;
  final bool isDischarging;

  /// Null means the payload did not report the link, which must not be read as
  /// down. False is an explicit "no BMS link".
  final bool? bmsLinkUp;
  final int? secondsSinceLastTelemetry;
  final int? expectedIntervalSeconds;
}

/// A pack is only called imbalanced when the cell view would already say
/// "Check cells": `JKBMSRCellVoltageGrid.balanceLabel` treats <=10 mV as very
/// balanced and <=30 mV as balanced. Reusing that boundary keeps the card and
/// the cell screen from disagreeing about the same pack.
const int _kCellSpreadAttentionMv = 30;

/// 2.5 V is the conventional LiFePO4 discharge cutoff and the app's own
/// default minimum cell voltage (SettingsScreen's `2.5` initial value).
const double _kCellCutoffVolts = 2.5;

/// The app's temperature tiles already treat >=50 °C as "Hot" and paint it
/// critical (`temperature_tiles.dart`, `_tempMood` / `_tempColor`). Reusing
/// that boundary means the card never contradicts the dashboard.
const double _kHighTemperatureC = 50.0;

/// Explicit engineering choice: the app does not know where the two pack
/// sensors are mounted, so only a 10 °C gap is surfaced. The finding states
/// the two readings as facts; it does not claim one sensor is wrong.
const double _kTemperatureSpreadC = 10.0;

/// Explicit engineering choice: 0.5 C is a conservative continuous rate for
/// LiFePO4 cells (many prismatic cells are rated at 1 C continuous), so a pack
/// at or above it near either end of its range is worth naming.
const double _kHighCRate = 0.5;

/// Explicit engineering choice: the bottom/top tenth of the range is where a
/// weaker cell reaches its own cutoff before the pack average does.
const double _kLowSocPercent = 10.0;
const double _kHighSocPercent = 95.0;

/// Explicit engineering choice: tolerate two missed uploads before calling a
/// gateway stopped. The cadence itself is the gateway's own
/// `expectedIntervalSeconds`, not a fixed guess.
const int _kMissedReportFactor = 3;

/// The most findings the card will render, so it stays a summary rather than a
/// second alarm list. Any others are counted in
/// [PackCheckReport.hiddenFindings] rather than dropped silently. Critical
/// findings sort ahead of attention findings, so the ones that matter most
/// survive the cap.
const int _kMaxRenderedFindings = 3;

/// Evaluates every gateway and combines the results into one card report.
/// [coverageNote] is carried through verbatim for the card to show when some
/// gateways could not be read.
PackCheckReport evaluatePackCheck(
  List<PackCheckInput> packs, {
  String? coverageNote,
}) {
  if (packs.isEmpty) {
    return PackCheckReport.noData(
      coverageNote == null
          ? 'No gateway telemetry is available to check.'
          : 'No gateway telemetry could be read.',
      coverageNote: coverageNote,
    );
  }

  final perPack = packs.map(_evaluatePack).toList(growable: false);
  final note = _withNoDataNote(coverageNote, perPack);

  final allFindings = <PackCheckFinding>[
    for (final report in perPack) ...report.findings,
  ];

  if (allFindings.isNotEmpty) {
    allFindings.sort(_bySeverityThenName);
    final shown = allFindings.take(_kMaxRenderedFindings).toList(growable: false);
    return PackCheckReport(
      verdict: PackCheckVerdict.findings,
      findings: shown,
      coverageNote: note,
      hiddenFindings: allFindings.length - shown.length,
    );
  }

  final clear = perPack
      .where((report) => report.verdict == PackCheckVerdict.clear)
      .toList(growable: false);
  if (clear.isNotEmpty) {
    return PackCheckReport(
      verdict: PackCheckVerdict.clear,
      facts: [for (final report in clear) ...report.facts],
      coverageNote: note,
    );
  }

  if (packs.length == 1) {
    final reason = perPack.first.noDataReason;
    if (reason != null) {
      return PackCheckReport.noData(reason, coverageNote: coverageNote);
    }
  }
  return PackCheckReport.noData(
    'None of the gateways reported cell, temperature or charge values.',
    coverageNote: coverageNote,
  );
}

int _bySeverityThenName(PackCheckFinding a, PackCheckFinding b) {
  // Enum order is attention (0), critical (1); higher severity sorts first.
  final bySeverity = b.severity.index.compareTo(a.severity.index);
  if (bySeverity != 0) return bySeverity;
  return a.deviceName.compareTo(b.deviceName);
}

/// Adds a count of gateways whose readings were missing, so a card that found
/// something (or found nothing) on one pack never reads as if it inspected the
/// others too.
String? _withNoDataNote(
  String? coverageNote,
  List<PackCheckReport> perPack,
) {
  final noData = perPack
      .where((report) => report.verdict == PackCheckVerdict.insufficientData)
      .length;
  if (noData == 0) return coverageNote;

  final note = '$noData of ${perPack.length} gateways had no readings to check.';
  if (coverageNote == null || coverageNote.isEmpty) return note;
  return '$coverageNote $note';
}

PackCheckReport _evaluatePack(PackCheckInput pack) {
  // A gateway can heartbeat with a dead BMS link, leaving every reading stale
  // or empty. Say that and skip the numeric checks: running them on numbers
  // nobody is currently measuring would attribute a condition to the pack.
  if (pack.bmsLinkUp == false) {
    return PackCheckReport(
      verdict: PackCheckVerdict.findings,
      findings: [
        PackCheckFinding(
          deviceName: pack.deviceName,
          severity: PackCheckSeverity.attention,
          title: 'No live readings from the battery',
          detail: 'The gateway reports no link to the BMS, so the cell, '
              'temperature and charge checks were skipped.',
        ),
      ],
    );
  }

  final findings = <PackCheckFinding>[];
  final facts = <String>[];

  final stale = _staleGatewayFinding(pack);
  if (stale != null) findings.add(stale);

  var hasPackReading = false;

  if (pack.hasTelemetry) {
    if (pack.cellVoltages.length >= 2) {
      hasPackReading = true;
      final spread = _cellSpread(pack.cellVoltages);
      facts.add('${pack.cellVoltages.length} cells · ${spread.spreadMv} mV spread');
      if (spread.spreadMv > _kCellSpreadAttentionMv) {
        findings.add(_cellSpreadFinding(pack, spread));
      }
    }

    // The API fills omitted numeric fields with 0, so a non-positive
    // temperature is treated as unreported rather than shown as a measurement.
    // The card currently checks heat only, not cold.
    final temps = <double>[
      if (pack.temperature1C != null && pack.temperature1C! > 0) pack.temperature1C!,
      if (pack.temperature2C != null && pack.temperature2C! > 0) pack.temperature2C!,
    ];
    if (temps.isNotEmpty) {
      hasPackReading = true;
      final hottest = temps.reduce((a, b) => a > b ? a : b);
      facts.add('${hottest.toStringAsFixed(1)} °C');
      if (hottest >= _kHighTemperatureC) {
        findings.add(
          PackCheckFinding(
            deviceName: pack.deviceName,
            severity: PackCheckSeverity.critical,
            title: 'Pack temperature is ${hottest.toStringAsFixed(1)} °C',
            detail: '50 °C is the app\'s own "Hot" boundary. Most LiFePO4 '
                'cells are only charged up to 45 °C.',
          ),
        );
      }

      final t1 = pack.temperature1C;
      final t2 = pack.temperature2C;
      if (t1 != null && t2 != null && t1 > 0 && t2 > 0) {
        final gap = (t1 - t2).abs();
        if (gap >= _kTemperatureSpreadC) {
          findings.add(
            PackCheckFinding(
              deviceName: pack.deviceName,
              severity: PackCheckSeverity.attention,
              title: 'Temperature sensors read ${gap.toStringAsFixed(1)} °C apart',
              detail: 'Sensor 1: ${t1.toStringAsFixed(1)} °C · '
                  'Sensor 2: ${t2.toStringAsFixed(1)} °C. The app does not '
                  'know where each sensor is mounted.',
            ),
          );
        }
      }
    }

    if (pack.socPercent != null) {
      hasPackReading = true;
      facts.add('${pack.socPercent!.round()}% charge');
      final socFinding = _socUnderLoadFinding(pack);
      if (socFinding != null) findings.add(socFinding);
    }
  }

  if (findings.isNotEmpty) {
    return PackCheckReport(
      verdict: PackCheckVerdict.findings,
      findings: findings,
    );
  }

  if (!hasPackReading) {
    return PackCheckReport.noData(_noDataReason(pack));
  }

  final prefix = pack.deviceName.trim().isEmpty ? '' : '${pack.deviceName}: ';
  return PackCheckReport(
    verdict: PackCheckVerdict.clear,
    facts: ['$prefix${facts.join(' · ')}'],
  );
}

String _noDataReason(PackCheckInput pack) {
  if (!pack.hasTelemetry) {
    if (pack.secondsSinceLastTelemetry == null) {
      return '${pack.deviceName} has not reported telemetry yet.';
    }
    return '${pack.deviceName} has no current telemetry to check.';
  }
  return '${pack.deviceName} did not report cell, temperature or charge values.';
}

PackCheckFinding? _staleGatewayFinding(PackCheckInput pack) {
  final since = pack.secondsSinceLastTelemetry;
  final expected = pack.expectedIntervalSeconds;
  if (since == null || expected == null || expected <= 0) return null;
  if (since <= expected * _kMissedReportFactor) return null;

  return PackCheckFinding(
    deviceName: pack.deviceName,
    severity: PackCheckSeverity.attention,
    title: 'Gateway has stopped reporting',
    detail: 'Last upload ${_formatDuration(since)} ago; this gateway '
        'reports every ${_formatDuration(expected)}.',
  );
}

class _CellSpread {
  const _CellSpread({
    required this.spreadMv,
    required this.maxVolts,
    required this.minVolts,
    required this.maxCell,
    required this.minCell,
  });

  final int spreadMv;
  final double maxVolts;
  final double minVolts;
  final int maxCell;
  final int minCell;
}

_CellSpread _cellSpread(List<double> volts) {
  var maxVolts = volts.first;
  var minVolts = volts.first;
  var maxIndex = 0;
  var minIndex = 0;
  for (var i = 1; i < volts.length; i++) {
    final v = volts[i];
    if (v > maxVolts) {
      maxVolts = v;
      maxIndex = i;
    }
    if (v < minVolts) {
      minVolts = v;
      minIndex = i;
    }
  }
  return _CellSpread(
    spreadMv: ((maxVolts - minVolts) * 1000).round(),
    maxVolts: maxVolts,
    minVolts: minVolts,
    maxCell: maxIndex + 1,
    minCell: minIndex + 1,
  );
}

PackCheckFinding _cellSpreadFinding(PackCheckInput pack, _CellSpread spread) {
  final atCutoff = spread.minVolts <= _kCellCutoffVolts;
  final title = atCutoff
      ? 'Cell ${spread.minCell} is reported at ${spread.minVolts.toStringAsFixed(2)} V'
      : 'Cell ${spread.maxCell} is ${spread.spreadMv} mV above cell ${spread.minCell}';
  return PackCheckFinding(
    deviceName: pack.deviceName,
    severity: atCutoff ? PackCheckSeverity.critical : PackCheckSeverity.attention,
    title: title,
    detail: 'Max ${spread.maxVolts.toStringAsFixed(3)} V · '
        'min ${spread.minVolts.toStringAsFixed(3)} V · '
        'spread ${spread.spreadMv} mV. The cell view calls a pack balanced '
        'up to 30 mV.'
        '${atCutoff ? ' 2.5 V is the conventional LiFePO4 cutoff and the '
            'app\'s default minimum.' : ''}',
  );
}

PackCheckFinding? _socUnderLoadFinding(PackCheckInput pack) {
  final soc = pack.socPercent;
  final capacity = pack.fullCapacityAh;
  final current = pack.currentAmps;
  if (soc == null || capacity == null || capacity <= 0 || current == null) {
    return null;
  }

  final cRate = current.abs() / capacity;
  if (cRate < _kHighCRate) return null;

  if (pack.isDischarging && soc <= _kLowSocPercent) {
    return PackCheckFinding(
      deviceName: pack.deviceName,
      severity: PackCheckSeverity.attention,
      title: 'Pack is at ${soc.round()}% and being discharged at '
          '${current.abs().toStringAsFixed(1)} A',
      detail: 'About ${cRate.toStringAsFixed(1)} C from a ${capacity.toStringAsFixed(0)} Ah pack. '
          'At the bottom of the range the weakest cell reaches its cutoff first.',
    );
  }

  if (pack.isCharging && soc >= _kHighSocPercent) {
    return PackCheckFinding(
      deviceName: pack.deviceName,
      severity: PackCheckSeverity.attention,
      title: 'Pack is at ${soc.round()}% and being charged at '
          '${current.abs().toStringAsFixed(1)} A',
      detail: 'About ${cRate.toStringAsFixed(1)} C into a ${capacity.toStringAsFixed(0)} Ah pack. '
          'At the top of the range the fullest cell reaches its cutoff first.',
    );
  }

  return null;
}

String _formatDuration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
}
