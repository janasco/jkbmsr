import 'package:flutter/material.dart';

import '../../../widgets/shared/design_system/colors.dart';
import '../../../widgets/shared/design_system/tokens.dart';
import '../../../widgets/shared/design_system/typography.dart';

/// KPI tile strip in the web style: centered value + sublabel tiles in a
/// wrapping row (label on top, bold mono value, muted sublabel). Purely
/// presentational — callers pass already-computed display strings.
class JKBMSRKpiTileData {
  final String label;
  final String value;
  final String sublabel;
  final Color? valueColor;

  const JKBMSRKpiTileData({
    required this.label,
    required this.value,
    required this.sublabel,
    this.valueColor,
  });
}

class JKBMSRKpiStrip extends StatelessWidget {
  final List<JKBMSRKpiTileData> tiles;

  const JKBMSRKpiStrip({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Two columns on narrow phones, up to four across on wider screens.
        final columns = constraints.maxWidth < 360
            ? 2
            : constraints.maxWidth < 560
                ? 3
                : 4;
        const gap = JKBMSRTokens.space8;
        final itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: itemWidth,
                child: _KpiTile(tile: tile),
              ),
          ],
        );
      },
    );
  }
}

class _KpiTile extends StatelessWidget {
  final JKBMSRKpiTileData tile;

  const _KpiTile({required this.tile});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: JKBMSRTokens.space8,
        vertical: JKBMSRTokens.space8,
      ),
      decoration: BoxDecoration(
        color: context.colors.inset,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
        border: Border.all(color: context.colors.line.withValues(alpha: 0.6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tile.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: JKBMSRTypography.label.copyWith(
              color: context.colors.textMuted,
              fontSize: 11.0,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              tile.value,
              maxLines: 1,
              style: JKBMSRTypography.monoTechnical.copyWith(
                color: tile.valueColor ?? context.colors.textPrimary,
                fontSize: 16.0,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            tile.sublabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: JKBMSRTypography.label.copyWith(
              color: context.colors.textMuted,
              fontSize: 10.0,
            ),
          ),
        ],
      ),
    );
  }
}
