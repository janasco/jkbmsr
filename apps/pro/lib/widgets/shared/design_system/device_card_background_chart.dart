import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'colors.dart';
import '../../../models/telemetry_history_point.dart';

/// Ambient Current/Power wave behind a gateway card, mirroring jkbmsr-web's
/// DeviceCardBackgroundChart. Purely decorative — the real Current/Power
/// values are already shown as labeled text stats in front of this, so: no
/// legend, no touch interaction, and it's excluded from the semantics tree
/// rather than announced as a second, unlabeled data source.
class DeviceCardBackgroundChart extends StatelessWidget {
  final List<TelemetryHistoryPoint> points;

  const DeviceCardBackgroundChart({Key? key, required this.points})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const SizedBox.shrink();

    // Same duotone as web: one hue (accent) nudged toward signal for the
    // second series, rather than two unrelated hues — deliberate, since this
    // chart is decorative and tuned for a cohesive wash, not run through the
    // usual categorical CVD-separation gate.
    final powerColor = context.colors.accent;
    final currentColor =
        Color.lerp(context.colors.accent, context.colors.signal, 0.22)!;

    return ExcludeSemantics(
      child: IgnorePointer(
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: 1,
            lineBarsData: [
              _series(points.map((p) => p.power).toList(), powerColor),
              _series(points.map((p) => p.current).toList(), currentColor),
            ],
            titlesData: const FlTitlesData(show: false),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
          ),
        ),
      ),
    );
  }

  LineChartBarData _series(List<double> values, Color color) {
    final normalized = _normalizedValues(values);
    return LineChartBarData(
      spots: [
        for (var i = 0; i < normalized.length; i++)
          FlSpot(i.toDouble(), normalized[i])
      ],
      isCurved: true,
      color: color.withValues(alpha: 0.45),
      barWidth: 1.5,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0)],
        ),
      ),
    );
  }

  List<double> _normalizedValues(List<double> values) {
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final range = (maxV - minV) == 0 ? 1 : (maxV - minV);
    return values.map((v) => (v - minV) / range).toList();
  }
}
