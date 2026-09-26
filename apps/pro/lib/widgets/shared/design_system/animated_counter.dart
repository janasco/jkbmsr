import 'package:flutter/material.dart';
import 'typography.dart';

/// An animated number counter that smoothly interpolates between values.
/// Used for SOC, voltage, temperature, and other live telemetry values
/// to give a polished, professional feel when numbers update.
class JKBMSRAnimatedCounter extends StatefulWidget {
  final double value;
  final String suffix;
  final TextStyle? style;
  final int decimalPlaces;
  final Duration duration;
  final Color? color;

  const JKBMSRAnimatedCounter({
    Key? key,
    required this.value,
    this.suffix = '',
    this.style,
    this.decimalPlaces = 1,
    this.duration = const Duration(milliseconds: 600),
    this.color,
  }) : super(key: key);

  @override
  State<JKBMSRAnimatedCounter> createState() => _JKBMSRAnimatedCounterState();
}

class _JKBMSRAnimatedCounterState extends State<JKBMSRAnimatedCounter>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _previousValue = 0;
  double _displayValue = 0;

  @override
  void initState() {
    super.initState();
    _previousValue = widget.value;
    _displayValue = widget.value;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.addListener(_onTick);
  }

  @override
  void didUpdateWidget(JKBMSRAnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _previousValue = _displayValue;
      _controller.forward(from: 0);
    }
  }

  void _onTick() {
    final t = _animation.value;
    setState(() {
      _displayValue = _previousValue + (widget.value - _previousValue) * t;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayText = _displayValue.toStringAsFixed(widget.decimalPlaces);
    return Text(
      '$displayText${widget.suffix}',
      style: (widget.style ?? JKBMSRTypography.pageHeading).copyWith(
        color: widget.color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// A compact animated counter designed for inline use (inside cards, rows).
/// Smaller default font size and shorter animation duration.
class JKBMSRAnimatedCounterCompact extends StatelessWidget {
  final double value;
  final String suffix;
  final int decimalPlaces;
  final TextStyle? style;
  final Color? color;

  const JKBMSRAnimatedCounterCompact({
    Key? key,
    required this.value,
    this.suffix = '',
    this.decimalPlaces = 1,
    this.style,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return JKBMSRAnimatedCounter(
      value: value,
      suffix: suffix,
      decimalPlaces: decimalPlaces,
      duration: const Duration(milliseconds: 400),
      color: color,
      style: style ?? JKBMSRTypography.body.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
