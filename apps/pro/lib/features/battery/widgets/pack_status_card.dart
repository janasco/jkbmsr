import 'package:flutter/material.dart';

import '../../../widgets/shared/design_system/colors.dart';
import '../../../widgets/shared/design_system/tokens.dart';
import '../../../widgets/shared/design_system/typography.dart';
import '../pack_status.dart';

/// A compact summary of what is set up on this gateway and what is not.
///
/// Presentation only: every decision about the lines, their marks and the
/// health sentence lives in [buildPackStatus]. The card never renders findings
/// from the pack check; the Alerts screen owns that detail and this only links
/// to it.
class PackStatusCard extends StatelessWidget {
  final PackStatusSummary summary;
  final VoidCallback onViewDetails;

  const PackStatusCard({
    Key? key,
    required this.summary,
    required this.onViewDetails,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
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
                Icons.checklist_rounded,
                size: 18,
                color: context.colors.textSecondary,
              ),
              const SizedBox(width: JKBMSRTokens.space8),
              Expanded(
                child: Text(
                  'Pack status',
                  style: JKBMSRTypography.cardHeading.copyWith(fontSize: 15.0),
                ),
              ),
            ],
          ),
          const SizedBox(height: JKBMSRTokens.space12),
          for (final line in summary.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: JKBMSRTokens.space8),
              child: _StatusLine(line: line),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: JKBMSRTokens.space4),
            child: Divider(height: 1, color: context.colors.line),
          ),
          const SizedBox(height: JKBMSRTokens.space8),
          _HealthRow(health: summary.health),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onViewDetails,
              style: TextButton.styleFrom(
                foregroundColor: context.colors.signal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 0,
                  vertical: JKBMSRTokens.space4,
                ),
                minimumSize: const Size(0, 44),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'View pack check',
                    style: JKBMSRTypography.bodySecondary.copyWith(
                      color: context.colors.signal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: JKBMSRTokens.space4),
                  Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: context.colors.signal,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final PackStatusLine line;

  const _StatusLine({required this.line});

  @override
  Widget build(BuildContext context) {
    final color = _markColor(context, line.mark);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(_markIcon(line.mark), size: 16, color: color),
        ),
        const SizedBox(width: JKBMSRTokens.space8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                line.label,
                style: JKBMSRTypography.bodySecondary.copyWith(
                  color: context.colors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: JKBMSRTokens.space2),
              Text(
                line.detail,
                style: JKBMSRTypography.label.copyWith(
                  color: context.colors.textMuted,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _markIcon(PackStatusMark mark) {
    switch (mark) {
      case PackStatusMark.done:
        return Icons.check_circle_outline;
      case PackStatusMark.pending:
        return Icons.radio_button_unchecked;
      case PackStatusMark.unknown:
        return Icons.help_outline;
    }
  }

  Color _markColor(BuildContext context, PackStatusMark mark) {
    switch (mark) {
      case PackStatusMark.done:
        return context.colors.accent;
      case PackStatusMark.pending:
        return context.colors.warning;
      case PackStatusMark.unknown:
        return context.colors.textMuted;
    }
  }
}

class _HealthRow extends StatelessWidget {
  final PackStatusHealth health;

  const _HealthRow({required this.health});

  @override
  Widget build(BuildContext context) {
    final color = _healthColor(context, health.tone);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(_healthIcon(health.tone), size: 18, color: color),
        ),
        const SizedBox(width: JKBMSRTokens.space8),
        Expanded(
          child: Text(
            health.sentence,
            style: JKBMSRTypography.bodySecondary.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  IconData _healthIcon(PackStatusHealthTone tone) {
    switch (tone) {
      case PackStatusHealthTone.clear:
        return Icons.check_circle_outline;
      case PackStatusHealthTone.attention:
        return Icons.warning_amber_rounded;
      case PackStatusHealthTone.critical:
        return Icons.error_outline;
      case PackStatusHealthTone.unknown:
        return Icons.info_outline;
    }
  }

  Color _healthColor(BuildContext context, PackStatusHealthTone tone) {
    switch (tone) {
      case PackStatusHealthTone.clear:
        return context.colors.accent;
      case PackStatusHealthTone.attention:
        return context.colors.warning;
      case PackStatusHealthTone.critical:
        return context.colors.critical;
      case PackStatusHealthTone.unknown:
        return context.colors.textMuted;
    }
  }
}
