import 'package:flutter/material.dart';

import '../../../widgets/shared/design_system/colors.dart';
import '../../../widgets/shared/design_system/tokens.dart';
import '../../../widgets/shared/design_system/typography.dart';
import '../cell_insight.dart';

/// A short explanation of the cell readings above it.
///
/// The words come from [CellInsight]; this widget only supplies colour and
/// layout. When [insight] is null it renders nothing at all, so a payload with
/// no comparable cell voltages is never replaced by a placeholder claim.
class CellInsightPanel extends StatelessWidget {
  final CellInsight? insight;

  const CellInsightPanel({Key? key, required this.insight}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final data = insight;
    if (data == null) return const SizedBox.shrink();

    final accent =
        data.needsAttention ? context.colors.warning : context.colors.accent;

    return Container(
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
            data.needsAttention
                ? Icons.warning_amber_rounded
                : Icons.balance_outlined,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: JKBMSRTokens.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.readingsLine,
                  style: JKBMSRTypography.bodySecondary.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: JKBMSRTokens.space4),
                Text(
                  data.meaningLine,
                  style: JKBMSRTypography.bodySecondary.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
