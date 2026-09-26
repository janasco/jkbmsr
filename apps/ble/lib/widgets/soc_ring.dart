import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion_kit.dart';

/// Circular state-of-charge gauge — the headline element of the redesigned
/// dashboard (adopted from the reference layouts). Draws a 270° arc track
/// with an animated value arc and the percentage centred inside, colour-coded
/// by the same thresholds the hero card uses.
///
/// When [live] is false the arc stays empty and the centre shows "—" so the
/// widget never renders a placeholder reading as if it were real (see the
/// hasLiveData note in ble_service.dart).
class SocRing extends StatelessWidget {
  final double percent; // 0..100
  final bool live;
  final Color color;
  final double size;
  final String caption;

  const SocRing({
    super.key,
    required this.percent,
    required this.live,
    required this.color,
    this.size = 120,
    this.caption = 'SOC',
  });

  @override
  Widget build(BuildContext context) {
    final target = live ? (percent.clamp(0.0, 100.0)) / 100.0 : 0.0;
    const track = Color(0xFF64748B);
    final semanticsLabel = live
        ? 'State of charge ${percent.toStringAsFixed(0)} percent'
        : 'State of charge unavailable';

    return Semantics(
        label: semanticsLabel,
        excludeSemantics: true,
        child: SizedBox(
          width: size,
          height: size,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: target),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              return CustomPaint(
                painter:
                    _RingPainter(progress: value, color: live ? color : track),
                child: Center(
                  // The percentage + caption must stay inside the fixed-size
                  // ring. At large OS text scales they outgrow it (a 34px
                  // overflow at textScale 2.0), so scale the whole centre
                  // block down to fit — a no-op at the default scale.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AnimatedNumber(
                              value: percent,
                              formatted: (v) => live ? v.toStringAsFixed(0) : '—',
                              style: TextStyle(
                                fontSize: size * 0.26,
                                fontWeight: FontWeight.w800,
                                height: 1.0,
                                color: live ? color : track,
                              ),
                            ),
                            if (live)
                              Padding(
                                padding: EdgeInsets.only(top: size * 0.02),
                                child: Text(
                                  '%',
                                  style: TextStyle(
                                    fontSize: size * 0.12,
                                    fontWeight: FontWeight.bold,
                                    color: color,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          caption,
                          style: const TextStyle(
                            fontSize: 11.0,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ));
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RingPainter({required this.progress, required this.color});

  // 270° arc, opening at the bottom (like most battery gauges).
  static const double _startAngle = 135 * math.pi / 180;
  static const double _sweepAngle = 270 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.085;
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.15);
    canvas.drawArc(rect, _startAngle, _sweepAngle, false, trackPaint);

    final clamped = progress.clamp(0.0, 1.0);
    if (clamped <= 0) return;
    final valuePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, _startAngle, _sweepAngle * clamped, false, valuePaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}
