import 'package:flutter/material.dart';

import '../../widgets/shared/design_system/colors.dart';
import '../../widgets/shared/design_system/tokens.dart';
import '../../widgets/shared/design_system/typography.dart';
import 'pack_check.dart';

/// The Alerts screen's "Pack check" card: one to three plain-language
/// findings, each beside the numbers that justify it.
///
/// The card is deliberately presentation-only. Every decision lives in
/// [evaluatePackCheck], so the wording here cannot disagree with the logic and
/// the card is testable without the alerts network flow.
class PackCheckCard extends StatelessWidget {
  final PackCheckReport? report;
  final bool isLoading;

  const PackCheckCard({Key? key, this.report, this.isLoading = false})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        JKBMSRTokens.space16,
        JKBMSRTokens.space12,
        JKBMSRTokens.space16,
        JKBMSRTokens.space4,
      ),
      padding: const EdgeInsets.all(JKBMSRTokens.space16),
      decoration: BoxDecoration(
        color: context.colors.panel,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
        border: Border.all(color: context.colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.fact_check_outlined,
                size: 18,
                color: _accentColor(context),
              ),
              const SizedBox(width: JKBMSRTokens.space8),
              Expanded(
                child: Text(
                  'Pack check',
                  style: JKBMSRTypography.cardHeading.copyWith(fontSize: 15.0),
                ),
              ),
            ],
          ),
          const SizedBox(height: JKBMSRTokens.space8),
          if (isLoading)
            _mutedLine(context, 'Reading the latest telemetry…')
          else if (report == null)
            _noData(
              context,
              'The latest readings could not be loaded.',
            )
          else if (report!.verdict == PackCheckVerdict.insufficientData)
            _noData(
              context,
              report!.noDataReason ??
                  'The latest readings did not include enough values.',
            )
          else if (report!.verdict == PackCheckVerdict.clear)
            _clear(context, report!)
          else
            _findings(context, report!),
          if (!isLoading && report?.coverageNote != null) ...[
            const SizedBox(height: JKBMSRTokens.space8),
            Text(
              report!.coverageNote!,
              style: JKBMSRTypography.label.copyWith(
                color: context.colors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _accentColor(BuildContext context) {
    final current = report;
    if (current == null || current.verdict == PackCheckVerdict.insufficientData) {
      return context.colors.textMuted;
    }
    if (current.verdict == PackCheckVerdict.clear) {
      return context.colors.accent;
    }
    final hasCritical = current.findings
        .any((finding) => finding.severity == PackCheckSeverity.critical);
    return hasCritical ? context.colors.critical : context.colors.warning;
  }

  Widget _mutedLine(BuildContext context, String text) {
    return Text(
      text,
      style: JKBMSRTypography.bodySecondary.copyWith(
        color: context.colors.textMuted,
      ),
    );
  }

  Widget _noData(BuildContext context, String reason) {
    return _headlineWithBody(
      context,
      icon: Icons.info_outline,
      color: context.colors.textMuted,
      title: 'Not enough data to check the pack',
      body: reason,
    );
  }

  Widget _clear(BuildContext context, PackCheckReport current) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _headlineWithBody(
          context,
          icon: Icons.check_circle_outline,
          color: context.colors.accent,
          title: 'The readings that could be checked look normal.',
          body: null,
        ),
        if (current.facts.isNotEmpty) ...[
          const SizedBox(height: JKBMSRTokens.space4),
          for (final fact in current.facts)
            Padding(
              padding: const EdgeInsets.only(top: JKBMSRTokens.space2),
              child: Text(
                fact,
                style: JKBMSRTypography.bodySecondary.copyWith(
                  color: context.colors.textMuted,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _findings(BuildContext context, PackCheckReport current) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < current.findings.length; i++)
          Padding(
            padding: EdgeInsets.only(
              top: i == 0 ? 0 : JKBMSRTokens.space12,
            ),
            child: _finding(context, current.findings[i]),
          ),
        if (current.hiddenFindings > 0) ...[
          const SizedBox(height: JKBMSRTokens.space8),
          Text(
            '${current.hiddenFindings} more '
            '${current.hiddenFindings == 1 ? 'finding' : 'findings'} not shown.',
            style: JKBMSRTypography.label.copyWith(
              color: context.colors.textMuted,
            ),
          ),
        ],
      ],
    );
  }

  Widget _finding(BuildContext context, PackCheckFinding finding) {
    final critical = finding.severity == PackCheckSeverity.critical;
    final color = critical ? context.colors.critical : context.colors.warning;
    final detail = finding.deviceName.trim().isEmpty
        ? finding.detail
        : '${finding.deviceName} · ${finding.detail}';

    return _headlineWithBody(
      context,
      icon: critical ? Icons.error_outline : Icons.warning_amber_rounded,
      color: color,
      title: finding.title,
      body: detail,
    );
  }

  Widget _headlineWithBody(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String? body,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: JKBMSRTokens.space8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: JKBMSRTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (body != null && body.isNotEmpty) ...[
                const SizedBox(height: JKBMSRTokens.space2),
                Text(
                  body,
                  style: JKBMSRTypography.bodySecondary.copyWith(
                    color: context.colors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
