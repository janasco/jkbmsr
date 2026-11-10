import 'package:flutter/material.dart';

import '../../../widgets/shared/design_system/colors.dart';
import '../../../widgets/shared/design_system/components.dart';
import '../../../widgets/shared/design_system/tokens.dart';
import '../../../widgets/shared/design_system/typography.dart';
import '../cell_detail.dart';

/// Opens the detail sheet for one cell.
Future<void> showCellDetailSheet(BuildContext context, CellDetail detail) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => CellDetailSheet(detail: detail),
  );
}

/// What one cell reads against the rest of its pack, plus what the gateway does
/// and does not store about it.
class CellDetailSheet extends StatelessWidget {
  final CellDetail detail;

  const CellDetailSheet({Key? key, required this.detail}) : super(key: key);

  static const String noHistoryTitle = 'No per-cell history';
  static const String noHistoryBody =
      'The gateway records pack voltage, current and power over time, not '
      'individual cell voltages. There is no stored chart for this cell.';

  @override
  Widget build(BuildContext context) {
    final role = detail.roleValue;
    final roleColor = detail.isWeakest
        ? context.colors.warning
        : detail.isStrongest
            ? context.colors.accent
            : context.colors.textSecondary;
    final deviationColor = detail.isWeakest
        ? context.colors.warning
        : detail.isStrongest
            ? context.colors.accent
            : context.colors.textSecondary;

    return JKBMSRBottomSheet(
      title: detail.title,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          JKBMSRTokens.space24,
          0,
          JKBMSRTokens.space24,
          JKBMSRTokens.space24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                detail.voltageValue,
                maxLines: 1,
                style: JKBMSRTypography.monoTechnical.copyWith(
                  fontSize: 30.0,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            if (role != null) ...[
              const SizedBox(height: JKBMSRTokens.space8),
              Text(
                role,
                style: JKBMSRTypography.bodySecondary.copyWith(
                  color: roleColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: JKBMSRTokens.space16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(JKBMSRTokens.space12),
              decoration: BoxDecoration(
                color: context.colors.inset,
                borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
              ),
              child: Column(
                children: [
                  _FactRow(
                    label: 'Deviation',
                    value: detail.deviationValue,
                    valueColor: deviationColor,
                  ),
                  const SizedBox(height: JKBMSRTokens.space8),
                  _FactRow(
                    label: 'Pack average',
                    value: detail.averageValue,
                  ),
                  const SizedBox(height: JKBMSRTokens.space8),
                  _FactRow(
                    label: 'Pack spread',
                    value: detail.spreadValue,
                  ),
                  const SizedBox(height: JKBMSRTokens.space8),
                  _FactRow(
                    label: 'Balancing',
                    value: detail.balancingValue,
                  ),
                ],
              ),
            ),
            const SizedBox(height: JKBMSRTokens.space12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(JKBMSRTokens.space12),
              decoration: BoxDecoration(
                color: context.colors.inset,
                borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.history_toggle_off,
                    size: 18,
                    color: context.colors.textMuted,
                  ),
                  const SizedBox(width: JKBMSRTokens.space8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          noHistoryTitle,
                          style: JKBMSRTypography.bodySecondary.copyWith(
                            color: context.colors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: JKBMSRTokens.space4),
                        Text(
                          noHistoryBody,
                          style: JKBMSRTypography.bodySecondary.copyWith(
                            color: context.colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One label/value pair. Both sides are flexed so a long value wraps inside the
/// card at large text scales instead of painting an overflow stripe.
class _FactRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _FactRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: JKBMSRTypography.label.copyWith(
              color: context.colors.textMuted,
            ),
          ),
        ),
        const SizedBox(width: JKBMSRTokens.space12),
        Expanded(
          flex: 6,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: JKBMSRTypography.bodySecondary.copyWith(
              color: valueColor ?? context.colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
