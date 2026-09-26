import 'package:flutter/material.dart';
import '../models/bms_models.dart';

class BatteryMetricsGrid extends StatelessWidget {
  final BmsStatus status;
  final bool isConnected;
  const BatteryMetricsGrid({super.key, required this.status, required this.isConnected});

  static String _formatDuration(int seconds) {
    if (seconds <= 0) return '0m';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF131A20) : const Color(0xFFFFFFFF);
    final borderColor = isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final mutedText = const Color(0xFF64748B);

    // Grow the fixed grid-tile height with the OS text scale so the label
    // and value lines never clip at large accessibility sizes. At the default
    // scale this is exactly 1.0, so the layout is unchanged.
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;

    final metrics = [
      _MetricItem(label: 'CAPACITY', value: '${status.nominalCapacityAh.toStringAsFixed(1)} Ah', highlight: false),
      _MetricItem(label: 'REMAINING CAPACITY', value: '${status.remainingCapacityAh.toStringAsFixed(1)} Ah', highlight: false),
      _MetricItem(label: 'CYCLE CAPACITY', value: '${status.totalCycleCapacityAh.toStringAsFixed(1)} Ah', highlight: false),
      _MetricItem(label: 'CYCLE COUNT', value: '${status.cycleCount}', highlight: false),
      _MetricItem(label: 'AVERAGE CELL VOLTAGE', value: '${status.averageCellVoltage.toStringAsFixed(3)} V', highlight: true),
      _MetricItem(label: 'CELL DIFFERENCE', value: '${status.deltaVoltageMv} mV', highlight: true),
      _MetricItem(label: 'ACTIVE CELL COUNT', value: '${status.cells.length}', highlight: false),
      _MetricItem(label: 'BALANCE CURRENT', value: '${status.balanceCurrentA.toStringAsFixed(1)} A', highlight: false),
      _MetricItem(label: 'CELL TYPE', value: status.cellType, highlight: false),
      _MetricItem(label: 'TIME ENTER SLEEP', value: _formatDuration(status.timeEnterSleepSec), highlight: false),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Battery details',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // Fixed tile height (instead of a width-derived aspect ratio) scaled
          // with the OS text size, so the label + value never clip.
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 68 * textScale,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: metrics.length,
          itemBuilder: (context, index) {
            final item = metrics[index];
            // Per-tile entrance stagger: each tile slides up + fades in
            // slightly after the previous one. The tween starts negative to
            // model the per-index delay, so no extra timer/controller is
            // needed and it runs once on first build only.
            return _TileEntrance(
              delayIndex: index,
              child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isConnected ? cardBg : cardBg.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontSize: 11.0,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      color: Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    isConnected ? item.value : '—',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: !isConnected
                          ? mutedText
                          : item.highlight
                              ? const Color(0xFF0284C7)
                              : textPrimary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            );
          },
        ),
      ],
    );
  }
}

/// Slide-up + fade entrance for one grid tile, delayed by [delayIndex]
/// steps. Animated once when the tile first mounts; telemetry updates after
/// that don't re-run it (the tween's end never changes).
class _TileEntrance extends StatelessWidget {
  final int delayIndex;
  final Widget child;

  const _TileEntrance({required this.delayIndex, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: -delayIndex * 0.06, end: 1.0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        final p = t.clamp(0.0, 1.0);
        return Opacity(
          opacity: p,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - p)),
            child: child,
          ),
        );
      },
    );
  }
}

class _MetricItem {
  final String label;
  final String value;
  final bool highlight;

  _MetricItem({
    required this.label,
    required this.value,
    required this.highlight,
  });
}
