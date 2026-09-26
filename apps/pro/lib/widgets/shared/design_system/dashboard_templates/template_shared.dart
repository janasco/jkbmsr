import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../colors.dart';
import '../tokens.dart';
import '../typography.dart';
import '../../../../models/telemetry.dart';

/// Shared building blocks for the alternate dashboard templates
/// (classic_dark_template.dart, gauge_sparkline_template.dart,
/// icon_tiles_template.dart, status_pills_template.dart,
/// terminal_readout_template.dart, severity_gauge_template.dart,
/// mosaic_grid_template.dart, at_a_glance_strip_template.dart) — mirrors
/// jkbmsr-web's src/components/devices/templateShared.tsx so the mobile and
/// web ports of the same template stay visually consistent.

enum TemplateBadgeTone { positive, critical, muted }

/// A small filled status pill (e.g. "Online", "Error", "Balancing") — mirrors
/// jkbmsr-web's `<StatusBadge>` (src/components/ui/StatusBadge.tsx), just
/// collapsed to the 3 tones the dashboard templates actually use.
class TemplateBadge extends StatelessWidget {
  final String label;
  final TemplateBadgeTone tone;

  const TemplateBadge({Key? key, required this.label, required this.tone}) : super(key: key);

  Color _color(BuildContext context) {
    switch (tone) {
      case TemplateBadgeTone.positive:
        return context.colors.accent;
      case TemplateBadgeTone.critical:
        return context.colors.critical;
      case TemplateBadgeTone.muted:
        return context.colors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: JKBMSRTokens.space8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: JKBMSRTypography.label.copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}

const _kSocSeverityBands = [
  (max: 20.0, color: _SeverityBand.critical),
  (max: 50.0, color: _SeverityBand.warning),
  (max: 100.0, color: _SeverityBand.signal),
];

enum _SeverityBand { critical, warning, signal }

/// Semicircular gauge with a red/yellow/blue danger-zone track (rather than
/// TemplateGauge's flat single-tone track) so low SoC stands out at a
/// glance — mirrors jkbmsr-web's `<SeverityGauge>`. The fill color switches
/// to whichever zone the current value falls in, same bands as
/// SOC_SEVERITY_BANDS in templateShared.tsx.
class TemplateSeverityGauge extends StatelessWidget {
  final double percent; // 0.0 - 1.0
  final String valueLabel;
  final String subLabel;

  const TemplateSeverityGauge({Key? key, required this.percent, required this.valueLabel, required this.subLabel}) : super(key: key);

  Color _bandColor(BuildContext context, _SeverityBand band) {
    switch (band) {
      case _SeverityBand.critical:
        return context.colors.critical;
      case _SeverityBand.warning:
        return context.colors.warning;
      case _SeverityBand.signal:
        return context.colors.signal;
    }
  }

  @override
  Widget build(BuildContext context) {
    final clamped = percent.clamp(0.0, 1.0);
    final valuePercent = clamped * 100;
    final currentBand = _kSocSeverityBands.firstWhere((band) => valuePercent <= band.max, orElse: () => _kSocSeverityBands.last).color;
    final segments = [
      for (var i = 0; i < _kSocSeverityBands.length; i++)
        (
          start: i == 0 ? 0.0 : _kSocSeverityBands[i - 1].max / 100,
          end: _kSocSeverityBands[i].max / 100,
          color: _bandColor(context, _kSocSeverityBands[i].color),
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 56,
          width: double.infinity,
          child: CustomPaint(
            painter: _SeverityGaugePainter(percent: clamped, segments: segments, fillColor: _bandColor(context, currentBand)),
          ),
        ),
        const SizedBox(height: JKBMSRTokens.space4),
        Text(valueLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: JKBMSRTypography.cardHeading.copyWith(color: context.colors.textPrimary)),
        Text(subLabel, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted)),
      ],
    );
  }
}

class _SeverityGaugePainter extends CustomPainter {
  final double percent;
  final List<({double start, double end, Color color})> segments;
  final Color fillColor;

  _SeverityGaugePainter({required this.percent, required this.segments, required this.fillColor});

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.height * 0.22;
    final radius = size.height - strokeWidth / 2;
    final center = Offset(size.width / 2, size.height);
    final rect = Rect.fromCircle(center: center, radius: radius);

    for (final segment in segments) {
      final trackPaint = Paint()
        ..color = segment.color.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawArc(rect, math.pi + math.pi * segment.start, math.pi * (segment.end - segment.start), false, trackPaint);
    }

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi * percent, false, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _SeverityGaugePainter oldDelegate) {
    return oldDelegate.percent != percent || oldDelegate.fillColor != fillColor;
  }
}

class TemplateStatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool on;

  const TemplateStatusPill({Key? key, required this.icon, required this.label, required this.on}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = on ? context.colors.accent : context.colors.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        // Shrinks + ellipsizes instead of overflowing when the OS text scale
        // makes "Discharge: OFF" wider than the status row it sits in.
        Flexible(
          child: Text.rich(
            TextSpan(
              style: JKBMSRTypography.bodySecondary.copyWith(color: context.colors.textSecondary),
              children: [
                TextSpan(text: '$label: '),
                TextSpan(text: on ? 'ON' : 'OFF', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class TemplateStatusRow extends StatelessWidget {
  final String lastSeen;
  final BmsExtras bms;

  const TemplateStatusRow({Key? key, required this.lastSeen, required this.bms}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(JKBMSRTokens.space12),
      decoration: BoxDecoration(color: context.colors.inset, borderRadius: BorderRadius.circular(JKBMSRTokens.radius8)),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: JKBMSRTokens.space12,
        runSpacing: JKBMSRTokens.space8,
        children: [
          Text.rich(
            TextSpan(
              style: JKBMSRTypography.bodySecondary.copyWith(color: context.colors.textSecondary),
              children: [
                const TextSpan(text: 'Last update: '),
                TextSpan(text: lastSeen, style: TextStyle(color: context.colors.signal, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Wrap(
            spacing: JKBMSRTokens.space16,
            runSpacing: JKBMSRTokens.space8,
            children: [
              TemplateStatusPill(icon: Icons.battery_charging_full, label: 'Charge', on: bms.charging),
              TemplateStatusPill(icon: Icons.arrow_downward, label: 'Discharge', on: bms.discharging),
              TemplateStatusPill(icon: Icons.compare_arrows, label: 'Balance', on: bms.balancing),
            ],
          ),
        ],
      ),
    );
  }
}

class TemplateDetailItem {
  final IconData icon;
  final String label;
  final String value;

  const TemplateDetailItem({required this.icon, required this.label, required this.value});
}

/// Icon-led, responsive grid of label/value details — e.g. "Rated Capacity:
/// 280 Ah". Replaces a raw Row-of-Text-pairs layout that used to overflow
/// on narrow phones (neither the label nor the value could shrink or wrap,
/// so a long label like "Remaining Capacity:" plus its value routinely
/// exceeded a ~150dp half-screen column). Column count is computed from
/// the actual available width instead of being hardcoded, and every label/
/// value truncates safely instead of forcing a RenderFlex overflow.
class TemplateDetailPanel extends StatelessWidget {
  final List<TemplateDetailItem> items;
  final String? title;

  const TemplateDetailPanel({Key? key, required this.items, this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const minItemWidth = 148.0;
        final columns = (constraints.maxWidth / minItemWidth).floor().clamp(1, 2);
        final gap = JKBMSRTokens.space12;
        final itemWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[
              Text(title!, style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted, fontWeight: FontWeight.w700)),
              const SizedBox(height: JKBMSRTokens.space12),
            ],
            Wrap(
              spacing: gap,
              runSpacing: JKBMSRTokens.space12,
              children: [
                for (final item in items) SizedBox(width: itemWidth, child: _TemplateDetailTile(item: item)),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _TemplateDetailTile extends StatelessWidget {
  final TemplateDetailItem item;

  const _TemplateDetailTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: context.colors.accent.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(item.icon, size: 14, color: context.colors.accent),
        ),
        const SizedBox(width: JKBMSRTokens.space8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted, letterSpacing: 0.2, fontWeight: FontWeight.w500),
              ),
              Text(
                item.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: JKBMSRTypography.monoTechnical.copyWith(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Headline stat (e.g. the big Voltage/Current/Power numbers) — the value
/// scales down to fit rather than overflowing when squeezed into a
/// multi-column row on a narrow phone or under a larger system font size.
class TemplateStatCard extends StatelessWidget {
  final IconData? icon;
  final String label;
  final String value;
  final String? sub;
  final Color? valueColor;

  const TemplateStatCard({Key? key, this.icon, required this.label, required this.value, this.sub, this.valueColor}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = valueColor ?? context.colors.accent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: color.withValues(alpha: 0.85)),
          const SizedBox(height: JKBMSRTokens.space4),
        ],
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted),
        ),
        const SizedBox(height: JKBMSRTokens.space4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, maxLines: 1, style: JKBMSRTypography.cardHeading.copyWith(color: color)),
        ),
        if (sub != null)
          Text(
            sub!,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: JKBMSRTypography.label.copyWith(color: context.colors.textSecondary),
          ),
      ],
    );
  }
}

class _ReadOnlySwitch extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool on;

  const _ReadOnlySwitch({required this.icon, required this.label, required this.on});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: JKBMSRTokens.space8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(icon, size: 16, color: context.colors.textSecondary),
                const SizedBox(width: JKBMSRTokens.space8),
                // The label must shrink/ellipsize rather than push the
                // read-only switch off the card at large accessibility sizes.
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: JKBMSRTypography.bodySecondary.copyWith(color: context.colors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 40,
            height: 22,
            padding: const EdgeInsets.all(2),
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: on ? context.colors.accent : context.colors.line,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(color: on ? context.colors.onAccent : context.colors.panel, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }
}

class TemplateSwitchesPanel extends StatelessWidget {
  final BmsExtras bms;

  const TemplateSwitchesPanel({Key? key, required this.bms}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(JKBMSRTokens.space12),
      decoration: BoxDecoration(color: context.colors.inset, borderRadius: BorderRadius.circular(JKBMSRTokens.radius8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReadOnlySwitch(icon: Icons.compare_arrows, label: 'Balancing', on: bms.balancing),
          _ReadOnlySwitch(icon: Icons.battery_charging_full, label: 'Charging', on: bms.charging),
          _ReadOnlySwitch(icon: Icons.arrow_downward, label: 'Discharging', on: bms.discharging),
          const SizedBox(height: JKBMSRTokens.space4),
          Text(
            'Read-only — reflects the BMS\'s current state.',
            style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Compact filled trend line, e.g. a device's recent voltage/current — not a
/// full interactive chart (no axes, grid, or touch), matching web's
/// hand-rolled SVG sparkline's look with fl_chart instead (already a
/// dependency, already used the same way by
/// lib/features/history/telemetry_history_screen.dart).
class TemplateSparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double height;

  const TemplateSparkline({Key? key, required this.values, required this.color, this.height = 40}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('Not enough data yet', style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted)),
        ),
      );
    }
    final spots = [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])];
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: color,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.15)),
            ),
          ],
          titlesData: const FlTitlesData(show: false),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
        ),
      ),
    );
  }
}

/// Semicircular percent gauge (e.g. remaining capacity, SoC) — a
/// CustomPainter arc rather than a chart-library dependency, mirroring the
/// math behind web's SVG stroke-dasharray gauge.
class TemplateGauge extends StatelessWidget {
  final double percent; // 0.0 - 1.0
  final String valueLabel;
  final String subLabel;
  final Color color;

  const TemplateGauge({
    Key? key,
    required this.percent,
    required this.valueLabel,
    required this.subLabel,
    required this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 56,
          width: double.infinity,
          child: CustomPaint(
            painter: _GaugePainter(percent: percent.clamp(0.0, 1.0), trackColor: context.colors.line, fillColor: color),
          ),
        ),
        const SizedBox(height: JKBMSRTokens.space4),
        Text(valueLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: JKBMSRTypography.cardHeading.copyWith(color: context.colors.textPrimary)),
        Text(subLabel, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted)),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double percent;
  final Color trackColor;
  final Color fillColor;

  _GaugePainter({required this.percent, required this.trackColor, required this.fillColor});

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.height * 0.22;
    final radius = size.height - strokeWidth / 2;
    final center = Offset(size.width / 2, size.height);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, trackPaint);

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi * percent, false, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.percent != percent || oldDelegate.fillColor != fillColor || oldDelegate.trackColor != trackColor;
  }
}
