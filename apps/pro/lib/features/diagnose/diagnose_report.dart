import '../../models/telemetry.dart';
import '../alerts/pack_check.dart';

/// The guided diagnosis, as pure logic.
///
/// It owns **no thresholds of its own**. Every pack finding comes from
/// [evaluatePackCheck], the same call the Alerts screen and the dashboard make,
/// so a diagnosis screen can never tell an owner that a reading is fine while
/// the dashboard says it is not. What this adds is the two things a reading
/// cannot show on its own: whether the gateway reached the battery, and whether
/// the gateway reached us.
enum DiagnoseTone { clear, attention, critical, unknown }

class DiagnoseCheck {
  const DiagnoseCheck({
    required this.title,
    required this.tone,
    required this.detail,
    this.nextStep,
  });

  final String title;
  final DiagnoseTone tone;

  /// What the measurement says, stated from the value rather than described in
  /// the abstract.
  final String detail;

  /// What to do about it, when there is something to do. Null means there is
  /// nothing to act on, which is different from "we did not think of anything".
  final String? nextStep;
}

class DiagnoseReport {
  const DiagnoseReport({
    required this.headline,
    required this.tone,
    required this.checks,
    required this.facts,
    required this.hasData,
  });

  final String headline;
  final DiagnoseTone tone;
  final List<DiagnoseCheck> checks;

  /// The measurements the pack verdict was derived from, verbatim from the pack
  /// check. Shown because "check the cells" without a number is not a diagnosis.
  final List<String> facts;

  final bool hasData;
}

DiagnoseTone _toneFor(PackCheckSeverity severity) => severity == PackCheckSeverity.critical
    ? DiagnoseTone.critical
    : DiagnoseTone.attention;

/// Builds the report for one gateway.
///
/// [gatewayOnline] is the cloud-reachability answer, which is deliberately not
/// the same question as [link]'s bms link: a gateway can be online and healthy
/// while the short-range link to the pack is down.
DiagnoseReport buildDiagnoseReport({
  required PackCheckInput pack,
  required bool gatewayOnline,
  required BmsLinkDiagnostics link,
}) {
  final packReport = evaluatePackCheck([pack]);
  final checks = <DiagnoseCheck>[];

  for (final finding in packReport.findings) {
    checks.add(DiagnoseCheck(
      title: finding.title,
      tone: _toneFor(finding.severity),
      detail: finding.detail,
    ));
  }

  checks.add(_linkCheck(link));
  checks.add(_gatewayCheck(gatewayOnline));

  final hasData = pack.hasTelemetry;
  final anyCritical = checks.any((c) => c.tone == DiagnoseTone.critical);
  final attentionCount = checks.where((c) => c.tone == DiagnoseTone.attention).length;
  final anyUnknown = checks.any((c) => c.tone == DiagnoseTone.unknown);

  final DiagnoseTone tone;
  if (anyCritical) {
    tone = DiagnoseTone.critical;
  } else if (attentionCount > 0) {
    tone = DiagnoseTone.attention;
  } else if (!hasData || anyUnknown) {
    // A missing value is not a passing value. Saying "nothing looks wrong"
    // while the battery link is unreported is exactly the confident sentence
    // this screen exists to avoid.
    tone = DiagnoseTone.unknown;
  } else {
    tone = DiagnoseTone.clear;
  }

  final String headline;
  switch (tone) {
    case DiagnoseTone.critical:
      headline = 'Something in these readings needs attention now.';
      break;
    case DiagnoseTone.attention:
      headline = attentionCount == 1
          ? 'One thing is worth checking.'
          : '$attentionCount things are worth checking.';
      break;
    case DiagnoseTone.unknown:
      headline = !hasData
          ? (packReport.noDataReason ?? 'There are no current readings to check yet.')
          : 'Some values could not be checked.';
      break;
    case DiagnoseTone.clear:
      headline = 'Nothing looks wrong in these readings.';
      break;
  }

  return DiagnoseReport(
    headline: headline,
    tone: tone,
    checks: checks,
    facts: packReport.facts,
    hasData: hasData,
  );
}

DiagnoseCheck _linkCheck(BmsLinkDiagnostics link) {
  if (link.bmsLinkUp == null) {
    return const DiagnoseCheck(
      title: 'Battery link',
      tone: DiagnoseTone.unknown,
      detail:
          'The gateway has not reported whether it is connected to the battery. That is a missing value, not a passing one.',
      nextStep: 'Wait for the next gateway update, then check again.',
    );
  }

  if (link.bmsLinkUp == false) {
    final parts = <String>['The gateway is not connected to the battery right now.'];
    if (link.bleState.isNotEmpty) parts.add('Gateway BLE state: ${link.bleState}.');
    if (link.lastError.isNotEmpty) parts.add('Last error: ${link.lastError}.');
    return DiagnoseCheck(
      title: 'Battery link',
      tone: DiagnoseTone.attention,
      detail: parts.join(' '),
      nextStep:
          'Keep the gateway close to the battery, and out of a metal enclosure if it is inside one. It keeps retrying on its own.',
    );
  }

  final rssi = link.rssi;
  final reported = rssi > -128;
  return DiagnoseCheck(
    title: 'Battery link',
    tone: DiagnoseTone.clear,
    detail: reported
        ? 'The gateway is connected to the battery. Signal $rssi dBm.'
        : 'The gateway is connected to the battery. It did not report a signal strength.',
    nextStep:
        reported && rssi < -85
            ? 'The signal is weak. Moving the gateway closer to the battery will make drops less likely.'
            : null,
  );
}

DiagnoseCheck _gatewayCheck(bool gatewayOnline) {
  return DiagnoseCheck(
    title: 'Gateway connection',
    tone: gatewayOnline ? DiagnoseTone.clear : DiagnoseTone.attention,
    detail: gatewayOnline
        ? 'The gateway is reporting to the cloud.'
        : 'The gateway is not reporting to the cloud right now, so these readings are the last ones it sent.',
    nextStep: gatewayOnline
        ? null
        : 'Check that the gateway has power and that its Wi-Fi network is available.',
  );
}
