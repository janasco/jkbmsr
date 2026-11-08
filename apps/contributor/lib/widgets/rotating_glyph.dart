import 'dart:math';

import 'package:flutter/material.dart';

/// The glyph in the middle of the capture orb.
///
/// It changes with **progress**, not with a timer. That is deliberate: a
/// repeating timer keeps scheduling frames, which makes `pumpAndSettle` in a
/// widget test never settle and costs battery on a screen the user is already
/// watching. Progress is animated every frame anyway, so driving the icon from it
/// gives the same "the app is alive and working" motion for free — and the icon
/// changes are then reproducible, which is what a screenshot or a test needs.
///
/// The order is shuffled per mount so two captures do not march through the same
/// sequence; pass [seed] to pin it.
class RotatingGlyph extends StatefulWidget {
  const RotatingGlyph({
    super.key,
    required this.progress,
    this.size = 64,
    this.color,
    this.icons = defaultIcons,
    this.seed,
  });

  /// 0 to 1. The icon advances once per `1 / icons.length` of progress.
  final double progress;
  final double size;
  final Color? color;
  final List<IconData> icons;

  /// Pins the shuffle. Left null, the order is random per mount.
  final int? seed;

  /// Battery and energy shapes: this app is asking for a battery capture, so the
  /// motion should feel like the subject rather than like a generic spinner.
  static const List<IconData> defaultIcons = [
    Icons.battery_charging_full_rounded,
    Icons.bolt_rounded,
    Icons.electric_bolt_rounded,
    Icons.battery_5_bar_rounded,
    Icons.energy_savings_leaf_rounded,
    Icons.power_rounded,
    Icons.speed_rounded,
    Icons.memory_rounded,
    Icons.sensors_rounded,
    Icons.electric_meter_rounded,
    Icons.thermostat_rounded,
    Icons.insights_rounded,
  ];

  @override
  State<RotatingGlyph> createState() => _RotatingGlyphState();
}

class _RotatingGlyphState extends State<RotatingGlyph> {
  late List<IconData> _order = _shuffled();

  List<IconData> _shuffled() =>
      List<IconData>.of(widget.icons)
        ..shuffle(widget.seed == null ? null : Random(widget.seed!));

  @override
  void didUpdateWidget(RotatingGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.icons, widget.icons) || oldWidget.seed != widget.seed) {
      _order = _shuffled();
    }
  }

  int get _index {
    final p = widget.progress.clamp(0.0, 1.0);
    final i = (p * _order.length).floor();
    return i >= _order.length ? _order.length - 1 : i;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 360),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.7, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          ),
          child: child,
        ),
      ),
      child: Icon(
        _order[_index],
        key: ValueKey<int>(_index),
        size: widget.size,
        color: widget.color ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
