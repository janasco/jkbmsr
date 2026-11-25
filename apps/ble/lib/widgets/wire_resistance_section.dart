import 'package:flutter/material.dart';
import '../models/bms_models.dart';
import 'adaptive_grid.dart';
import 'motion_kit.dart';

class WireResistanceSection extends StatelessWidget {
  final List<CellInfo> cells;
  const WireResistanceSection({super.key, required this.cells});

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF131A20) : const Color(0xFFFFFFFF);
    final borderColor = isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

    // Grow the fixed grid-tile height with the OS text scale so the two text
    // lines never clip at large accessibility sizes, and derive the column
    // count from the same scale (see gridColumnsFor). The labels inside a
    // tile are 11 px, so the scale is taken from that size.
    final textScale = MediaQuery.textScalerOf(context).scale(11) / 11;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Wire resistance',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
        ),
        const Text(
          'Balance-lead resistance by cell',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 10),
        // ADAPTIVE-COLUMN GRID. Four columns at the default text scale; fewer
        // as the text grows, so a tile is never squeezed below the width its
        // own text needs.
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = gridColumnsFor(
              width: constraints.maxWidth,
              textScale: textScale,
            );
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              // Fixed tile height scaled with the OS text size so the two
              // text lines never clip at large accessibility scales.
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: 58 * textScale,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: cells.length,
              itemBuilder: (context, idx) {
            final cell = cells[idx];
            return TileEntrance(
              delayIndex: idx,
              child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'C${cell.index.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 11.0,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF64748B),
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    '${cell.resistanceMOhms.toStringAsFixed(1)}mΩ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: textPrimary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            );
              },
            );
          },
        ),
      ],
    );
  }
}
