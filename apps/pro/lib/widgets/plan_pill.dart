import 'package:flutter/material.dart';

import 'shared/design_system/colors.dart';
import 'shared/design_system/tokens.dart';
import 'shared/design_system/typography.dart';

/// Human-readable telemetry cadence for a Cloud Service tier: '30 sec',
/// '5 min', '1 hr'. Documented cases: 30 → '30 sec', 60 → '1 min',
/// 300 → '5 min', 900 → '15 min', 1800 → '30 min', 3600 → '1 hr'.
String formatPlanInterval(int seconds) {
  if (seconds < 60) return '$seconds sec';
  if (seconds % 3600 == 0) return '${seconds ~/ 3600} hr';
  return '${seconds ~/ 60} min';
}

/// Cloud Service plan pill: the gateway's entitled tier plus its telemetry
/// cadence (e.g. "Standard · every 1 min"). Shown in the battery dashboard
/// header so the reader can tell at a glance which plan sets the poll rate.
///
/// All values come from the device-config endpoint (`subscriptionTierLabel`,
/// `subscriptionTierIntervalSeconds`, `subscriptionStatus`); this widget only
/// renders them and never fetches.
class PlanPill extends StatelessWidget {
  final String tierLabel;
  final int intervalSeconds;
  final String status;
  final bool compact;

  const PlanPill({
    super.key,
    required this.tierLabel,
    required this.intervalSeconds,
    this.status = 'inactive',
    this.compact = false,
  });

  bool get _active => status.toLowerCase() == 'active';

  @override
  Widget build(BuildContext context) {
    final color = _active ? context.colors.accent : context.colors.textMuted;
    final label = '$tierLabel · every ${formatPlanInterval(intervalSeconds)}';
    return Semantics(
      label: '$label, ${_active ? 'active' : 'inactive'} plan',
      // Exclude the inner Text so screen readers announce the single
      // combined label above rather than it plus the visible text.
      child: ExcludeSemantics(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? JKBMSRTokens.space8 : JKBMSRTokens.space12,
            vertical: JKBMSRTokens.space4,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(JKBMSRTokens.radiusFull),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: JKBMSRTokens.space4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JKBMSRTypography.label.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
