import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../widgets/shared/design_system/colors.dart';

/// The scanning radar.
///
/// Deliberately **settle-safe**: the rings only animate while [active] and only
/// when the platform has not asked for reduced motion. A repeating animation
/// that ignores those two things keeps scheduling frames on an idle screen and
/// makes every widget test wait out its timeout, which is a cost this app has
/// already paid once.
class RadarPulse extends StatefulWidget {
  const RadarPulse({
    super.key,
    required this.active,
    this.size = 260,
    this.child,
    this.ringCount = 3,
    this.period = const Duration(milliseconds: 2400),
  });

  /// True only while a scan is actually running.
  final bool active;

  final double size;
  final Widget? child;
  final int ringCount;
  final Duration period;

  @override
  State<RadarPulse> createState() => _RadarPulseState();
}

class _RadarPulseState extends State<RadarPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  bool _reducedMotion = false;

  bool get _animating => widget.active && !_reducedMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(covariant RadarPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) {
      _controller.duration = widget.period;
    }
    _sync();
  }

  void _sync() {
    if (_animating) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      // Stop rather than reset: assigning a value here would notify listeners
      // during build, and the painter renders a static ring when it is not
      // animating anyway.
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<JKBMSRColors>()!;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _RadarPainter(
              progress: _controller.value,
              animating: _animating,
              ringColor: colors.accent,
              discColor: colors.accent.withValues(alpha: 0.08),
              ringCount: widget.ringCount,
            ),
            child: child,
          );
        },
        child: Center(
          child: Container(
            width: widget.size * 0.42,
            height: widget.size * 0.42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.accent.withValues(alpha: 0.12),
              border: Border.all(color: colors.accent.withValues(alpha: 0.35)),
            ),
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.progress,
    required this.animating,
    required this.ringColor,
    required this.discColor,
    required this.ringCount,
  });

  final double progress;
  final bool animating;
  final Color ringColor;
  final Color discColor;
  final int ringCount;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;
    final disc = Paint()..color = discColor;
    canvas.drawCircle(center, maxRadius * 0.92, disc);

    if (!animating) {
      // One quiet ring: the radar is present but not claiming to be working.
      canvas.drawCircle(
        center,
        maxRadius * 0.78,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = ringColor.withValues(alpha: 0.28),
      );
      return;
    }

    for (var i = 0; i < ringCount; i++) {
      final phase = (progress + i / ringCount) % 1.0;
      final radius = maxRadius * (0.32 + 0.64 * phase);
      final opacity = (1.0 - phase) * 0.5;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, 2.0 * (1 - phase))
          ..color = ringColor.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.animating != animating ||
      oldDelegate.ringColor != ringColor ||
      oldDelegate.ringCount != ringCount;
}
