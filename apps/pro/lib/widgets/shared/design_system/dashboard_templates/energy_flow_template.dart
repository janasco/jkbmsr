import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'template_shared.dart';
import '../colors.dart';
import '../tokens.dart';
import '../typography.dart';
import '../animated_counter.dart';
import '../../../../models/telemetry.dart';
import '../../../../models/telemetry_history_point.dart';

/// The hero dashboard: a big State-of-Charge ring with an animated energy
/// flow (pack ⇄ source/load) underneath, live voltage/current/power stats,
/// a voltage sparkline, and a cell-balance strip. Rendered for the
/// 'default' dashboard template key — i.e. what every existing gateway
/// shows — with the older card layouts still available via their named
/// template keys.
///
/// All numbers come straight from live telemetry; the only invented value
/// is the flow animation itself, which is purely decorative (direction and
/// color follow the real current sign, and it freezes when
/// [animationsEnabled] is false).
class JKBMSREnergyFlowTemplate extends StatefulWidget {
  final Telemetry? telemetry;
  final String lastSeen;
  final bool animationsEnabled;
  final List<TelemetryHistoryPoint> history;

  const JKBMSREnergyFlowTemplate({
    Key? key,
    required this.telemetry,
    required this.lastSeen,
    required this.history,
    this.animationsEnabled = true,
  }) : super(key: key);

  @override
  State<JKBMSREnergyFlowTemplate> createState() => _JKBMSREnergyFlowTemplateState();
}

/// Whether the OS asks for reduced motion; safe to read in initState.
bool _reduceMotion() =>
    WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;

class _JKBMSREnergyFlowTemplateState extends State<JKBMSREnergyFlowTemplate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flowController;

  @override
  void initState() {
    super.initState();
    _flowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (widget.animationsEnabled && !_reduceMotion()) {
      _flowController.repeat();
    }
  }

  @override
  void didUpdateWidget(JKBMSREnergyFlowTemplate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animationsEnabled != oldWidget.animationsEnabled) {
      if (widget.animationsEnabled && !_reduceMotion()) {
        _flowController.repeat();
      } else {
        _flowController.stop();
      }
    }
  }

  @override
  void dispose() {
    _flowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.telemetry;
    final bms = t?.bms;
    final current = t?.current ?? 0.0;
    final charging = current > 0.05;
    final discharging = current < -0.05;
    final idle = !charging && !discharging;
    final soc = (t?.soc ?? 0.0).clamp(0.0, 100.0);
    final socColor =
        soc < 20 ? context.colors.critical : soc < 50 ? context.colors.warning : context.colors.accent;
    final flowColor = charging
        ? context.colors.accent
        : discharging
            ? context.colors.signal
            : context.colors.textMuted;
    final voltageHistory = widget.history.map((point) => point.voltage).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(JKBMSRTokens.space16),
      decoration: BoxDecoration(
        color: context.colors.inset,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
        border: Border.all(color: context.colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hero: SOC ring ──
          Center(
            child: SizedBox(
              width: 190,
              height: 190,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(190, 190),
                    painter: _SocRingPainter(
                      percent: soc / 100,
                      ringColor: socColor,
                      trackColor: context.colors.line,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('STATE OF CHARGE',
                          style: JKBMSRTypography.label.copyWith(
                            color: context.colors.textMuted,
                            letterSpacing: 1.1,
                            fontSize: 11.0,
                          )),
                      const SizedBox(height: JKBMSRTokens.space4),
                      JKBMSRAnimatedCounter(
                        value: soc,
                        suffix: '%',
                        decimalPlaces: 0,
                        color: context.colors.textPrimary,
                        style: JKBMSRTypography.pageHeading.copyWith(fontSize: 44),
                      ),
                      const SizedBox(height: JKBMSRTokens.space4),
                      Text(
                        '${(bms?.remainingCapacityAh ?? 0.0).toStringAsFixed(1)} of ${(bms?.fullCapacityAh ?? 0.0).toStringAsFixed(0)} Ah',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: JKBMSRTypography.label.copyWith(color: context.colors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: JKBMSRTokens.space16),

          // ── Energy flow strip ──
          _EnergyFlowStrip(
            charging: charging,
            discharging: discharging,
            idle: idle,
            flowColor: flowColor,
            animation: _flowController,
            animationsEnabled: widget.animationsEnabled,
            powerW: t?.power ?? 0.0,
            currentA: current,
          ),
          const SizedBox(height: JKBMSRTokens.space16),

          // ── Live stats ──
          Row(
            children: [
              Expanded(
                child: TemplateStatCard(
                  icon: Icons.electrical_services,
                  label: 'VOLTAGE',
                  value: '${(t?.voltage ?? 0.0).toStringAsFixed(2)} V',
                  valueColor: context.colors.textPrimary,
                ),
              ),
              const SizedBox(width: JKBMSRTokens.space12),
              Expanded(
                child: TemplateStatCard(
                  icon: Icons.swap_vert,
                  label: 'CURRENT',
                  value: '${current.abs().toStringAsFixed(1)} A',
                  sub: charging ? 'charging in' : discharging ? 'drawing out' : 'idle',
                  valueColor: flowColor,
                ),
              ),
              const SizedBox(width: JKBMSRTokens.space12),
              Expanded(
                child: TemplateStatCard(
                  icon: Icons.flash_on,
                  label: 'POWER',
                  value: '${(t?.power ?? 0.0).abs().toStringAsFixed(0)} W',
                  valueColor: flowColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: JKBMSRTokens.space16),

          // ── Voltage trend ──
          if (voltageHistory.length >= 2) ...[
            Text('VOLTAGE TREND',
                style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted, letterSpacing: 0.8)),
            const SizedBox(height: JKBMSRTokens.space8),
            TemplateSparkline(values: voltageHistory, color: context.colors.accent, height: 44),
            const SizedBox(height: JKBMSRTokens.space16),
          ],

          // ── Cell balance strip ──
          if (bms != null && bms.avgCellVoltage > 0) ...[
            _CellBalanceStrip(bms: bms),
            const SizedBox(height: JKBMSRTokens.space16),
          ],

          // ── Status row ──
          TemplateStatusRow(lastSeen: widget.lastSeen, bms: bms ?? BmsExtras.fromJson(null)),
        ],
      ),
    );
  }
}

/// Circular SOC ring: full-circle track with a rounded fill arc starting at
/// 12 o'clock, plus a soft outer glow in the fill color at higher SOC.
class _SocRingPainter extends CustomPainter {
  final double percent; // 0.0 - 1.0
  final Color ringColor;
  final Color trackColor;

  _SocRingPainter({
    required this.percent,
    required this.ringColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.075;
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );

    // Subtle glow behind the filled portion.
    final glowPaint = Paint()
      ..color = ringColor.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 1.9
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * percent, false, glowPaint);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawArc(rect, 0, 2 * math.pi, false, trackPaint);

    final fillPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * percent, false, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _SocRingPainter oldDelegate) {
    return oldDelegate.percent != percent ||
        oldDelegate.ringColor != ringColor ||
        oldDelegate.trackColor != trackColor;
  }
}

/// Source → pack → load strip. Animated dots travel source→pack while
/// charging and pack→load while discharging; the active leg's label and
/// power figure light up in the flow color, the inactive leg stays muted.
class _EnergyFlowStrip extends StatelessWidget {
  final bool charging;
  final bool discharging;
  final bool idle;
  final Color flowColor;
  final Animation<double> animation;
  final bool animationsEnabled;
  final double powerW;
  final double currentA;

  const _EnergyFlowStrip({
    required this.charging,
    required this.discharging,
    required this.idle,
    required this.flowColor,
    required this.animation,
    required this.animationsEnabled,
    required this.powerW,
    required this.currentA,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: JKBMSRTokens.space12, vertical: JKBMSRTokens.space12),
      decoration: BoxDecoration(
        color: context.colors.panel,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
        border: Border.all(color: context.colors.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _flowNode(
                context,
                icon: Icons.wb_sunny,
                label: 'SOURCE',
                active: charging,
                activeColor: flowColor,
              ),
              Expanded(
                child: _FlowWire(
                  color: flowColor,
                  active: charging && animationsEnabled,
                  animation: animation,
                  leftToRight: true,
                  dimmed: !charging,
                  dimColor: context.colors.textMuted,
                ),
              ),
              _packNode(context),
              Expanded(
                child: _FlowWire(
                  color: flowColor,
                  active: discharging && animationsEnabled,
                  animation: animation,
                  leftToRight: true,
                  dimmed: !discharging,
                  dimColor: context.colors.textMuted,
                ),
              ),
              _flowNode(
                context,
                icon: Icons.home_outlined,
                label: 'LOAD',
                active: discharging,
                activeColor: flowColor,
              ),
            ],
          ),
          const SizedBox(height: JKBMSRTokens.space8),
          Text(
            idle
                ? 'No energy flow right now'
                : charging
                    ? 'Charging · +${powerW.abs().toStringAsFixed(0)} W in'
                    : 'Discharging · ${powerW.abs().toStringAsFixed(0)} W out',
            style: JKBMSRTypography.label.copyWith(
              color: idle ? context.colors.textMuted : flowColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _flowNode(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool active,
    required Color activeColor,
  }) {
    final color = active ? activeColor : context.colors.textMuted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? activeColor.withValues(alpha: 0.14) : context.colors.inset,
            shape: BoxShape.circle,
            border: Border.all(color: active ? activeColor.withValues(alpha: 0.5) : context.colors.line),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: JKBMSRTypography.label.copyWith(
              color: color,
              fontSize: 11.0,
              letterSpacing: 0.8,
            )),
      ],
    );
  }

  Widget _packNode(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.colors.accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: context.colors.accent.withValues(alpha: 0.5)),
          ),
          child: Icon(Icons.battery_charging_full, size: 24, color: context.colors.accent),
        ),
        const SizedBox(height: 4),
        Text('PACK',
            style: JKBMSRTypography.label.copyWith(
              color: context.colors.accent,
              fontSize: 11.0,
              letterSpacing: 0.8,
            )),
      ],
    );
  }
}

/// The animated wire between nodes: a thin track with three dots gliding
/// along it while [active]; renders as a static dashed line when dimmed.
class _FlowWire extends StatelessWidget {
  final Color color;
  final bool active;
  final Animation<double> animation;
  final bool leftToRight;
  final bool dimmed;
  final Color dimColor;

  const _FlowWire({
    required this.color,
    required this.active,
    required this.animation,
    required this.leftToRight,
    required this.dimmed,
    required this.dimColor,
  });

  @override
  Widget build(BuildContext context) {
    if (dimmed && !active) {
      return SizedBox(
        height: 24,
        child: CustomPaint(
          painter: _StaticWirePainter(color: dimColor.withValues(alpha: 0.5)),
          size: Size.infinite,
        ),
      );
    }
    return SizedBox(
      height: 24,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) => CustomPaint(
          painter: _FlowWirePainter(
            color: color,
            progress: animation.value,
            leftToRight: leftToRight,
            active: active,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _FlowWirePainter extends CustomPainter {
  final Color color;
  final double progress;
  final bool leftToRight;
  final bool active;

  _FlowWirePainter({
    required this.color,
    required this.progress,
    required this.leftToRight,
    required this.active,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final trackPaint = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), trackPaint);

    if (!active) return;

    const dotCount = 3;
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < dotCount; i++) {
      // Phase-offset particles; sine fade keeps them from popping at the ends.
      final t = (progress + i / dotCount) % 1.0;
      final alpha = math.sin(math.pi * t);
      final x = leftToRight ? t * size.width : (1 - t) * size.width;
      dotPaint.color = color.withValues(alpha: alpha.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, centerY), 3.0, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FlowWirePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.active != active ||
        oldDelegate.leftToRight != leftToRight;
  }
}

class _StaticWirePainter extends CustomPainter {
  final Color color;

  _StaticWirePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), paint);
  }

  @override
  bool shouldRepaint(covariant _StaticWirePainter oldDelegate) => oldDelegate.color != color;
}

/// Min/avg/max cell balance strip: a track spanning [min..max] cell voltage
/// with markers for each, so imbalance reads as marker spread. Delta is
/// shown in mV next to the label — green-scale coloring follows the same
/// thresholds the cell grid uses visually.
class _CellBalanceStrip extends StatelessWidget {
  final BmsExtras bms;

  const _CellBalanceStrip({required this.bms});

  @override
  Widget build(BuildContext context) {
    final deltaMv = (bms.deltaCellVoltage * 1000).round();
    final balanced = deltaMv <= 20;
    final stripColor = balanced ? context.colors.accent : context.colors.warning;

    // Track range: min/max cell voltage padded by ~15% of the delta so the
    // extreme markers never sit exactly on the strip edges (or collapse to
    // a point on a perfectly-balanced pack).
    final minV = bms.minCellVoltage;
    final maxV = bms.maxCellVoltage;
    final pad = ((maxV - minV) * 0.15).clamp(0.002, 0.05);
    final lo = minV - pad;
    final hi = maxV + pad;
    double pos(double v) => ((v - lo) / (hi - lo)).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(JKBMSRTokens.space12),
      decoration: BoxDecoration(
        color: context.colors.panel,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
        border: Border.all(color: context.colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('CELL BALANCE',
                  style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted, letterSpacing: 0.8)),
              Text(
                'Δ $deltaMv mV · cells ${bms.minVoltageCell}/${bms.maxVoltageCell}',
                style: JKBMSRTypography.label.copyWith(color: stripColor, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: JKBMSRTokens.space8),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return SizedBox(
                height: 18,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // Track
                    Container(
                      height: 6,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: context.colors.inset,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: context.colors.line),
                      ),
                    ),
                    // Average marker (wide, faint)
                    Positioned(
                      left: (pos(bms.avgCellVoltage) * width).clamp(0.0, width - 2),
                      child: Container(
                        width: 2,
                        height: 14,
                        color: stripColor.withValues(alpha: 0.55),
                      ),
                    ),
                    // Min marker
                    Positioned(
                      left: (pos(minV) * width).clamp(0.0, width - 8),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: context.colors.critical,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    // Max marker
                    Positioned(
                      left: (pos(maxV) * width).clamp(0.0, width - 8),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: context.colors.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: JKBMSRTokens.space8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _markerLabel(context, dotColor: context.colors.critical, text: 'min ${minV.toStringAsFixed(3)} V'),
              _markerLabel(context, dotColor: stripColor.withValues(alpha: 0.55), text: 'avg ${bms.avgCellVoltage.toStringAsFixed(3)} V'),
              _markerLabel(context, dotColor: context.colors.accent, text: 'max ${maxV.toStringAsFixed(3)} V'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _markerLabel(BuildContext context, {required Color dotColor, required String text}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(text, style: JKBMSRTypography.label.copyWith(color: context.colors.textSecondary, fontSize: 11.0)),
      ],
    );
  }
}
