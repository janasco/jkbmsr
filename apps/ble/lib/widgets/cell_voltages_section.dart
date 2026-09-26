import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/bms_models.dart';
import 'motion_kit.dart';

class CellVoltagesSection extends StatelessWidget {
  final List<CellInfo> cells;
  const CellVoltagesSection({super.key, required this.cells});

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF131A20) : const Color(0xFFFFFFFF);
    final borderColor = isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

    // Grow the fixed cell-matrix tile height with the OS text scale so the
    // cell id + voltage lines never clip at large accessibility sizes. At the
    // default scale this is exactly 1.0, so the layout is unchanged.
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;

    CellInfo minCell = cells[0];
    CellInfo maxCell = cells[0];
    double totalV = 0.0;

    for (var c in cells) {
      totalV += c.voltage;
      if (c.voltage < minCell.voltage) minCell = c;
      if (c.voltage > maxCell.voltage) maxCell = c;
    }

    final deltaMv = ((maxCell.voltage - minCell.voltage) * 1000).round();
    final avgV = totalV / cells.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cell voltages',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
                  ),
                  Text(
                    '${cells.length}-Cell active balance matrix',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // BALANCE SUMMARY — the reference's headline "cell balance" callout.
        _BalanceCallout(deltaMv: deltaMv, isDark: isDark, textPrimary: textPrimary),
        const SizedBox(height: 10),

        // SUMMARY BADGES (MIN & MAX)
        Row(
          children: [
            Expanded(
              child: PulseGlow(
                color: const Color(0xFFEF4444),
                borderRadius: 14,
                child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MIN CELL ${minCell.index.toString().padLeft(2, '0')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.0,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: Color(0xFFEF4444),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${minCell.voltage.toStringAsFixed(3)} V',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: textPrimary,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'MIN',
                        style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold, color: Color(0xFFEF4444)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PulseGlow(
                color: const Color(0xFF38BDF8),
                borderRadius: 14,
                child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MAX CELL ${maxCell.index.toString().padLeft(2, '0')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.0,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: Color(0xFF0284C7),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${maxCell.voltage.toStringAsFixed(3)} V',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: textPrimary,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'MAX',
                        style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // DELTA & AVERAGE
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(
                      child: Text('DELTA (DIFF)', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '$deltaMv mV',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF10B981), fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(
                      child: Text('AVERAGE', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${avgV.toStringAsFixed(3)} V',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: textPrimary, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // BALANCE TREND — pack ΔmV sampled over this session. As balancing
        // works the line falls; a flat/rising line means it isn't keeping up.
        _DeltaTrend(deltaMv: deltaMv, isDark: isDark, textPrimary: textPrimary),
        const SizedBox(height: 12),

        // PACK SPREAD SPARKLINE — one bar per cell, scaled between the
        // pack's min and max, so balance quality reads at a glance.
        _CellSparkline(cells: cells, minCell: minCell, maxCell: maxCell, avgV: avgV),
        const SizedBox(height: 6),

        // 4-COLUMN CELL MATRIX
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // Fixed cell height scaled with the OS text size so the id/voltage
          // lines never clip at large accessibility scales.
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisExtent: 64 * textScale,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemCount: cells.length,
          itemBuilder: (context, idx) {
            final cell = cells[idx];
            final isMin = cell.index == minCell.index;
            final isMax = cell.index == maxCell.index;
            final isBalancing = cell.isBalancing;
            // Target band: cells more than 20 mV off the pack average are
            // "outliers" worth a second look (see the balance callout above).
            final isOutlier = (cell.voltage - avgV).abs() > 0.02;

            Color cellBorder = borderColor;
            Color cellBg = cardBg;
            Color voltColor = textPrimary;

            if (isMin) {
              cellBorder = const Color(0xFFEF4444).withValues(alpha: 0.6);
              cellBg = isDark ? const Color(0xFF1F1517) : const Color(0xFFFEE2E2);
              voltColor = const Color(0xFFEF4444);
            } else if (isMax) {
              cellBorder = const Color(0xFF38BDF8).withValues(alpha: 0.6);
              cellBg = isDark ? const Color(0xFF121B24) : const Color(0xFFE0F2FE);
              voltColor = const Color(0xFF0284C7);
            } else if (isBalancing) {
              cellBorder = const Color(0xFF10B981).withValues(alpha: 0.6);
              cellBg = isDark ? const Color(0xFF0E1E18) : const Color(0xFFD1FAE5);
              voltColor = const Color(0xFF10B981);
            } else if (isOutlier) {
              cellBorder = const Color(0xFFF59E0B).withValues(alpha: 0.6);
              voltColor = const Color(0xFFF59E0B);
            }

            return TileEntrance(
              delayIndex: idx,
              child: GestureDetector(
              onTap: () => _showCellDetail(context, cell, avgV, minCell, maxCell),
              child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                color: cellBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cellBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'C${cell.index.toString().padLeft(2, '0')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontFamily: 'monospace'),
                        ),
                      ),
                      if (isMin)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text('MIN', style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: Colors.white)),
                        )
                      else if (isMax)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0284C7),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text('MAX', style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: Colors.white)),
                        )
                      else if (isBalancing)
                        const PulseDot(color: Color(0xFF10B981), size: 5),
                    ],
                  ),
                  Text(
                    '${cell.voltage.toStringAsFixed(3)}V',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: voltColor,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            ),
            );
          },
        ),
      ],
    );
  }

  /// Bottom sheet with a single cell's live detail — voltage, deviation from
  /// the pack average, balancing state, wire resistance, and whether it's the
  /// pack's current min/max (Cells-tab improvement #1).
  void _showCellDetail(
    BuildContext context,
    CellInfo cell,
    double avgV,
    CellInfo minCell,
    CellInfo maxCell,
  ) {
    final deviationMv = ((cell.voltage - avgV) * 1000).round();
    final rows = <(String, String)>[
      ('Voltage', '${cell.voltage.toStringAsFixed(3)} V'),
      ('Deviation from average', '${deviationMv >= 0 ? '+' : ''}$deviationMv mV'),
      ('Wire resistance', '${cell.resistanceMOhms.toStringAsFixed(1)} mΩ'),
      ('Balancing', cell.isBalancing ? 'Active' : 'Idle'),
      if (cell.index == minCell.index) ('Pack', 'Lowest cell'),
      if (cell.index == maxCell.index) ('Pack', 'Highest cell'),
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cell ${cell.index.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            for (final row in rows) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(row.$1, style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                    Text(
                      row.$2,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'monospace', fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (row != rows.last) const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tiny sparkline showing the pack's voltage spread: one bar per cell,
/// scaled between min and max, with the min cell in red and the max in
/// blue. A quick, alive way to see balance quality at a glance.
class _CellSparkline extends StatelessWidget {
  final List<CellInfo> cells;
  final CellInfo minCell;
  final CellInfo maxCell;
  final double avgV;

  const _CellSparkline({
    required this.cells,
    required this.minCell,
    required this.maxCell,
    required this.avgV,
  });

  @override
  Widget build(BuildContext context) {
    if (cells.length < 2) return const SizedBox.shrink();
    return SizedBox(
      // CustomPaint with no explicit width collapses to zero in a loose-width
      // column, which made the sparkline invisible (and asserted on a
      // negative bar radius in debug). Take the full row width instead.
      width: double.infinity,
      height: 36,
      child: CustomPaint(
        painter: _CellSparklinePainter(
          cells: cells,
          minIndex: minCell.index,
          maxIndex: maxCell.index,
          avgV: avgV,
        ),
      ),
    );
  }
}

class _CellSparklinePainter extends CustomPainter {
  final List<CellInfo> cells;
  final int minIndex;
  final int maxIndex;
  final double avgV;

  _CellSparklinePainter({
    required this.cells,
    required this.minIndex,
    required this.maxIndex,
    required this.avgV,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final voltages = cells.map((c) => c.voltage).toList();
    final minV = voltages.reduce(math.min);
    final maxV = voltages.reduce(math.max);
    final range = (maxV - minV).abs();

    const barGap = 2.0;
    final barWidth = math.max(
      0.0,
      (size.width - barGap * (cells.length - 1)) / cells.length,
    );
    // Too many cells for the available width — nothing sensible to draw, and
    // a zero/negative bar radius would assert.
    if (barWidth <= 0) return;

    final basePaint = Paint()..color = const Color(0xFF64748B).withValues(alpha: 0.45);
    final minPaint = Paint()..color = const Color(0xFFEF4444);
    final maxPaint = Paint()..color = const Color(0xFF38BDF8);

    // Target band (avg ± 20 mV): bars inside it are healthy; outside = amber
    // in the matrix below. Drawn behind the bars.
    double yFor(double v) {
      final norm = range < 0.0001 ? 0.5 : (v - minV) / range;
      final h = 4.0 + (size.height - 4.0) * norm.clamp(0.0, 1.0);
      return size.height - h;
    }

    final bandTop = yFor(avgV + 0.02);
    final bandBottom = yFor(avgV - 0.02);
    canvas.drawRect(
      Rect.fromLTRB(0, bandTop, size.width, bandBottom),
      Paint()..color = const Color(0xFF10B981).withValues(alpha: 0.12),
    );

    for (int i = 0; i < cells.length; i++) {
      final cell = cells[i];
      final hNorm = range < 0.0001
          ? 0.5
          : (cell.voltage - minV) / range;
      final barHeight = 4.0 + (size.height - 4.0) * hNorm;
      final rect = Rect.fromLTWH(
        i * (barWidth + barGap),
        size.height - barHeight,
        barWidth,
        barHeight,
      );
      final paint = cell.index == minIndex
          ? minPaint
          : cell.index == maxIndex
              ? maxPaint
              : basePaint;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barWidth / 3)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CellSparklinePainter old) =>
      old.minIndex != minIndex || old.maxIndex != maxIndex || old.avgV != avgV;
}

/// Headline "cell balance" state — a green all-balanced callout or an amber
/// imbalance warning, with the pack delta. Mirrors the reference layout's
/// balance summary.
class _BalanceCallout extends StatelessWidget {
  final int deltaMv;
  final bool isDark;
  final Color textPrimary;

  const _BalanceCallout({
    required this.deltaMv,
    required this.isDark,
    required this.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final balanced = deltaMv < 30;
    final color = balanced ? const Color(0xFF10B981) : const Color(0xFFF59E0B);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(balanced ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
              size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cell balance',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textPrimary)),
                Text(
                  balanced ? 'All cells balanced' : 'Imbalance detected — check connections',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          Text('Δ $deltaMv mV',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w900, color: color, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

/// Session balance trend — pack ΔmV sampled over time in an in-memory ring
/// buffer (one point per distinct reading, so it reflects the connected
/// session). Unlike the per-cell spread sparkline, this shows whether the pack
/// is converging or drifting while balancing runs.
class _DeltaTrend extends StatefulWidget {
  final int deltaMv;
  final bool isDark;
  final Color textPrimary;

  const _DeltaTrend({
    required this.deltaMv,
    required this.isDark,
    required this.textPrimary,
  });

  @override
  State<_DeltaTrend> createState() => _DeltaTrendState();
}

class _DeltaTrendState extends State<_DeltaTrend> {
  static const int _maxPoints = 120;
  final List<int> _history = [];

  @override
  void initState() {
    super.initState();
    _history.add(widget.deltaMv);
  }

  @override
  void didUpdateWidget(covariant _DeltaTrend oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.deltaMv != oldWidget.deltaMv) {
      _history.add(widget.deltaMv);
      if (_history.length > _maxPoints) _history.removeAt(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxV = _history.reduce(math.max);
    final minV = _history.reduce(math.min);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                'Balance trend',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: widget.textPrimary),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Δ ${widget.deltaMv} mV · ${_history.length} reading${_history.length == 1 ? '' : 's'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 11.0, color: Color(0xFF64748B)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 34,
          child: CustomPaint(
            size: Size.infinite,
            painter: _DeltaTrendPainter(
              history: _history,
              minV: minV,
              maxV: maxV,
              color: const Color(0xFF10B981),
            ),
          ),
        ),
      ],
    );
  }
}

class _DeltaTrendPainter extends CustomPainter {
  final List<int> history;
  final int minV;
  final int maxV;
  final Color color;

  _DeltaTrendPainter({
    required this.history,
    required this.minV,
    required this.maxV,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (history.length < 2) return;
    final range = (maxV - minV).abs();
    final dx = size.width / (history.length - 1);
    final path = Path();
    for (int i = 0; i < history.length; i++) {
      final norm = range == 0 ? 0.5 : (history[i] - minV) / range;
      final y = size.height - 2 - norm * (size.height - 4);
      final x = i * dx;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_DeltaTrendPainter old) =>
      old.history.length != history.length || old.minV != minV || old.maxV != maxV;
}
