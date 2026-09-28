import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Motion primitives for the JKBMSR BLE app — the "alive" layer.
///
/// Everything here is painter/state based (no assets, no extra deps) and
/// loops on long durations so the effects read as atmosphere and liveness,
/// never as noise. Palette matches AppColors: green 0xFF10B981,
/// blue 0xFF38BDF8, amber 0xFFF59E0B, red 0xFFEF4444.

// ─── Ambient background ──────────────────────────────────────────────────────

/// Slow-drifting glow fields + faint dot grid behind scrollable content.
///
/// Two blurred color fields (brand green and blue) drift on a 14s loop over
/// the canvas color, with a barely-visible dot grid on top. Repaints only
/// itself — the child subtree never rebuilds from the animation.
class JkAmbientBackground extends StatefulWidget {
  final Widget child;

  const JkAmbientBackground({super.key, required this.child});

  @override
  State<JkAmbientBackground> createState() => _JkAmbientBackgroundState();
}

/// Whether the OS asks for reduced motion. Read off the platform dispatcher
/// so it can be consulted from initState without a BuildContext.
bool _reducedMotion() =>
    WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;

class _JkAmbientBackgroundState extends State<JkAmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 14000),
    );
    if (!_reducedMotion()) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _AmbientPainter(
            t: _controller.value,
            isDark: isDark,
            bgCanvas: isDark ? const Color(0xFF090D10) : const Color(0xFFF8FAFC),
            accent: const Color(0xFF10B981),
            signal: const Color(0xFF38BDF8),
            line: isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0),
          ),
          child: widget.child,
        );
      },
    );
  }
}

class _AmbientPainter extends CustomPainter {
  final double t;
  final bool isDark;
  final Color bgCanvas;
  final Color accent;
  final Color signal;
  final Color line;

  _AmbientPainter({
    required this.t,
    required this.isDark,
    required this.bgCanvas,
    required this.accent,
    required this.signal,
    required this.line,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bgCanvas);

    final drift = (math.sin(2 * math.pi * t) + 1) / 2;
    final drift2 = (math.cos(2 * math.pi * t) + 1) / 2;

    final glow = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 90);

    canvas.drawCircle(
      Offset(size.width * (0.10 + 0.16 * drift), size.height * 0.06 + 0.08 * drift2 * size.height),
      size.width * 0.55,
      glow..color = accent.withValues(alpha: isDark ? 0.09 : 0.07),
    );
    canvas.drawCircle(
      Offset(size.width * (0.88 - 0.14 * drift2), size.height * (0.92 - 0.10 * drift)),
      size.width * 0.50,
      glow..color = signal.withValues(alpha: isDark ? 0.07 : 0.05),
    );

    const spacing = 26.0;
    final dot = Paint()..color = line.withValues(alpha: isDark ? 0.22 : 0.30);
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 0.7, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      old.t != t || old.isDark != isDark;
}

// ─── Pulse dot ───────────────────────────────────────────────────────────────

/// Heartbeat status dot with a soft halo pulse. Drop-in replacement for any
/// static colored circle that indicates connection / activity / scanning.
class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  final bool active;

  /// When false the dot renders static at full opacity (offline state).
  const PulseDot({super.key, required this.color, this.size = 8, this.active = true});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.active && !_reducedMotion()) _controller.repeat();
  }

  @override
  void didUpdateWidget(PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating && !_reducedMotion()) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
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
    if (!widget.active) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        // Heartbeat: rise → fall → small secondary bump → rest.
        double scale;
        if (t < 0.25) {
          scale = 1.0 + 0.3 * Curves.easeOut.transform(t / 0.25);
        } else if (t < 0.45) {
          scale = 1.3 - 0.3 * Curves.easeIn.transform((t - 0.25) / 0.2);
        } else if (t < 0.65) {
          scale = 1.0 + 0.15 * Curves.easeOut.transform((t - 0.45) / 0.2);
        } else {
          scale = 1.15 - 0.15 * Curves.easeIn.transform((t - 0.65) / 0.35);
        }
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.9),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.3 * scale),
                blurRadius: widget.size * 0.6 * scale,
                spreadRadius: widget.size * 0.1 * scale,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Animated number ─────────────────────────────────────────────────────────

/// Smoothly tweens between numeric values when telemetry updates, instead of
/// hard-cutting. Wraps [formatted] so the caller controls presentation.
class AnimatedNumber extends StatelessWidget {
  final double value;
  final String Function(double value) formatted;
  final TextStyle style;
  final Duration duration;

  const AnimatedNumber({
    super.key,
    required this.value,
    required this.formatted,
    required this.style,
    this.duration = const Duration(milliseconds: 500),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(formatted(v), style: style),
    );
  }
}

// ─── Radar sweep ─────────────────────────────────────────────────────────────

/// Rotating radar sweep for scanning states: spinning gradient wedge inside
/// fading range rings. Pure painter.
class ScanRadar extends StatefulWidget {
  final double size;
  final Color color;
  final bool spinning;

  const ScanRadar({
    super.key,
    this.size = 120,
    required this.color,
    this.spinning = true,
  });

  @override
  State<ScanRadar> createState() => _ScanRadarState();
}

class _ScanRadarState extends State<ScanRadar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    if (widget.spinning && !_reducedMotion()) _controller.repeat();
  }

  @override
  void didUpdateWidget(ScanRadar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning && !_controller.isAnimating && !_reducedMotion()) {
      _controller.repeat();
    } else if (!widget.spinning && _controller.isAnimating) {
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _RadarPainter(t: _controller.value, color: widget.color),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double t;
  final Color color;

  _RadarPainter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Fading range rings.
    for (final r in [1.0, 0.66, 0.33]) {
      canvas.drawCircle(
        center,
        radius * r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color.withValues(alpha: 0.18 + 0.10 * r),
      );
    }

    // Sweep wedge trailing the leading edge.
    final sweepAngle = 2 * math.pi * t;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final wedge = Paint()
      ..shader = SweepGradient(
        startAngle: sweepAngle - math.pi / 3,
        endAngle: sweepAngle,
        colors: [color.withValues(alpha: 0.0), color.withValues(alpha: 0.45)],
        transform: const GradientRotation(0),
      ).createShader(rect);
    canvas.drawCircle(center, radius, wedge);

    // Leading edge line.
    canvas.drawLine(
      center,
      center + Offset(math.cos(sweepAngle), math.sin(sweepAngle)) * radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.9),
    );

    // Center blip.
    canvas.drawCircle(center, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.t != t;
}

// ─── Staggered entrance ──────────────────────────────────────────────────────

/// Wraps each child in a slide-up + fade entrance, delayed by [stepMs] per
/// index. Use once per screen/section; children animate once on first build.
class StaggerIn extends StatefulWidget {
  final List<Widget> children;
  final int stepMs;

  const StaggerIn({super.key, required this.children, this.stepMs = 60});

  @override
  State<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<StaggerIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final int _totalMs;

  @override
  void initState() {
    super.initState();
    _totalMs = (widget.stepMs * (widget.children.length - 1) + 450)
        .clamp(400, 1600);
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _totalMs),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < widget.children.length; i++)
              _EntryItem(
                progress: _progressFor(i),
                child: widget.children[i],
              ),
          ],
        );
      },
    );
  }

  double _progressFor(int index) {
    final startMs = index * widget.stepMs;
    const revealMs = 450;
    final t =
        ((_controller.value * _totalMs - startMs) / revealMs).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(t);
  }
}

class _EntryItem extends StatelessWidget {
  final double progress;
  final Widget child;

  const _EntryItem({required this.progress, required this.child});

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, 20 * (1 - progress)),
      child: Opacity(opacity: progress.clamp(0.0, 1.0), child: child),
    );
  }
}

// ─── Charging sheen ──────────────────────────────────────────────────────────

/// A soft light band that sweeps across its child on a loop. Used on the SOC
/// banner and charge indicators to signal active energy flow.
class ChargingSheen extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final Color tint;

  const ChargingSheen({
    super.key,
    required this.child,
    required this.enabled,
    required this.tint,
  });

  @override
  State<ChargingSheen> createState() => _ChargingSheenState();
}

class _ChargingSheenState extends State<ChargingSheen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (widget.enabled && !_reducedMotion()) _controller.repeat();
  }

  @override
  void didUpdateWidget(ChargingSheen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_controller.isAnimating && !_reducedMotion()) {
      _controller.repeat();
    } else if (!widget.enabled && _controller.isAnimating) {
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
    if (!widget.enabled) return widget.child;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _SheenPainter(
                      t: _controller.value,
                      tint: widget.tint,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheenPainter extends CustomPainter {
  final double t;
  final Color tint;

  _SheenPainter({required this.t, required this.tint});

  @override
  void paint(Canvas canvas, Size size) {
    final x = -size.width * 0.5 + (size.width * 2.0) * t;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          tint.withValues(alpha: 0.0),
          tint.withValues(alpha: 0.10),
          tint.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(x, 0, size.width * 0.5, size.height));
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_SheenPainter old) => old.t != t;
}

// ─── Pulse glow ──────────────────────────────────────────────────

/// Breathing glow halo rendered behind [child] — used to draw the eye to
/// the MIN/MAX cells, live-verified brand chip, and other key states.
/// Wrap OUTSIDE the decorated widget so the glow paints behind its border.
class PulseGlow extends StatefulWidget {
  final Widget child;
  final Color color;
  final bool enabled;
  final double borderRadius;

  const PulseGlow({
    super.key,
    required this.child,
    required this.color,
    this.enabled = true,
    this.borderRadius = 14,
  });

  @override
  State<PulseGlow> createState() => _PulseGlowState();
}

class _PulseGlowState extends State<PulseGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    // Unlike every sibling primitive here, this one used to start its loop
    // unconditionally, so the breathing glow kept animating for users who had
    // asked the OS to disable animations. didUpdateWidget already consulted
    // _reducedMotion(); initState now matches it.
    if (widget.enabled && !_reducedMotion()) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(PulseGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_controller.isAnimating && !_reducedMotion()) {
      _controller.repeat(reverse: true);
    } else if (!widget.enabled && _controller.isAnimating) {
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
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.10 + 0.16 * t),
                blurRadius: 10 + 8 * t,
                spreadRadius: 1 + 1.5 * t,
              ),
            ],
          ),
          child: widget.child,
        );
      },
    );
  }
}

// ─── Grid tile entrance ──────────────────────────────────────────────

/// Slide-up + fade entrance for one grid tile, delayed by [delayIndex]
/// steps of 40ms. Animates once when the tile first mounts; telemetry
/// updates after that never re-run it (the tween's end never changes).
/// The tween starts negative to model the delay — no timers or controllers.
class TileEntrance extends StatelessWidget {
  final int delayIndex;
  final Widget child;

  const TileEntrance({super.key, required this.delayIndex, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: -delayIndex * 0.04, end: 1.0),
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

// ─── Animated dots text ──────────────────────────────────────────────

/// Cycles "…", "…", "…" style trailing dots for loading/scanning labels.
class AnimatedDots extends StatefulWidget {
  final String base;
  final TextStyle style;

  const AnimatedDots({super.key, required this.base, required this.style});

  @override
  State<AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<AnimatedDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (!_reducedMotion()) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final count = (_controller.value * 3).floor() + 1;
        return Text(
          widget.base + '.' * count,
          style: widget.style,
        );
      },
    );
  }
}
