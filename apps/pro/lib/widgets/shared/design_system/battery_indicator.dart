import 'package:flutter/material.dart';
import 'colors.dart';

/// A battery-shaped fill gauge (body + terminal nub) with smooth animated charging
/// and discharging progress bar effects.
class JKBMSRBatteryIndicator extends StatefulWidget {
  final double percent; // 0.0 - 1.0
  final double width;
  final double height;
  final bool isCharging;
  final bool isDischarging;
  final int cellIndex;
  final bool animationsEnabled;

  const JKBMSRBatteryIndicator({
    Key? key,
    required this.percent,
    this.width = 64,
    this.height = 24,
    this.isCharging = false,
    this.isDischarging = false,
    this.cellIndex = 0,
    this.animationsEnabled = true,
  }) : super(key: key);

  @override
  State<JKBMSRBatteryIndicator> createState() => _JKBMSRBatteryIndicatorState();
}

/// Whether the OS asks for reduced motion; safe to read in initState.
bool _reduceMotion() => WidgetsBinding
    .instance.platformDispatcher.accessibilityFeatures.disableAnimations;

class _JKBMSRBatteryIndicatorState extends State<JKBMSRBatteryIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.animationsEnabled && !_reduceMotion()) {
      _animController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant JKBMSRBatteryIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animationsEnabled != oldWidget.animationsEnabled) {
      if (widget.animationsEnabled && !_reduceMotion()) {
        _animController.repeat();
      } else {
        _animController.stop();
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Color _fillColor(BuildContext context) {
    if (widget.percent < 0.2) return context.colors.critical;
    if (widget.percent < 0.4) return context.colors.warning;
    return context.colors.accent;
  }

  // Same charging/discharging color language as the animated fill, just
  // without the moving gradient/pulse, for when the user turns animations off.
  Widget _staticFill(Color fillColor) {
    final color = widget.isCharging
        ? context.colors.accent
        : widget.isDischarging
            ? context.colors.warning
            : fillColor;
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2)),
        ),
        if (widget.isCharging && widget.height >= 16)
          Center(
            child: Icon(Icons.bolt,
                size: widget.height * 0.7, color: Colors.white),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final clamped = widget.percent.clamp(0.0, 1.0);
    final fillColor = _fillColor(context);
    final nubWidth = widget.height * 0.2;
    final nubHeight = widget.height * 0.5;
    final semanticsLabel = widget.isCharging
        ? 'Battery ${(clamped * 100).round()} percent, charging'
        : widget.isDischarging
            ? 'Battery ${(clamped * 100).round()} percent, discharging'
            : 'Battery ${(clamped * 100).round()} percent';

    return Semantics(
        label: semanticsLabel,
        excludeSemantics: true,
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: widget.width - nubWidth - 1,
                height: widget.height,
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  border: Border.all(color: context.colors.line, width: 1.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutCubic,
                        width: constraints.maxWidth * clamped,
                        height: constraints.maxHeight,
                        child: !widget.animationsEnabled
                            ? _staticFill(fillColor)
                            : AnimatedBuilder(
                                animation: _animController,
                                builder: (context, child) {
                                  BoxDecoration dec;
                                  // Stagger animation phase per cell so each battery cell animates with a unique rhythm:
                                  final phaseShift =
                                      (widget.cellIndex * 0.23) % 1.0;
                                  final shift =
                                      (_animController.value + phaseShift) %
                                          1.0;
                                  if (widget.isCharging) {
                                    dec = BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          context.colors.accent,
                                          const Color(0xFF34D399),
                                          context.colors.accent,
                                          const Color(0xFF059669),
                                        ],
                                        stops: const [0.0, 0.4, 0.7, 1.0],
                                        begin: Alignment(
                                            -1.0 + (shift * 2.0), 0.0),
                                        end:
                                            Alignment(1.0 + (shift * 2.0), 0.0),
                                        tileMode: TileMode.mirror,
                                      ),
                                      borderRadius: BorderRadius.circular(2),
                                      boxShadow: [
                                        BoxShadow(
                                          color: context.colors.accent
                                              .withValues(alpha: 0.5),
                                          blurRadius: 4,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    );
                                  } else if (widget.isDischarging) {
                                    final pulse = (0.7 +
                                        0.3 * (1.0 - (0.5 - shift).abs() * 2));
                                    dec = BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          context.colors.warning
                                              .withValues(alpha: pulse),
                                          const Color(0xFFFBBF24),
                                          context.colors.warning
                                              .withValues(alpha: pulse),
                                        ],
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      ),
                                      borderRadius: BorderRadius.circular(2),
                                    );
                                  } else {
                                    dec = BoxDecoration(
                                      color: fillColor,
                                      borderRadius: BorderRadius.circular(2),
                                    );
                                  }

                                  return Stack(
                                    children: [
                                      Container(decoration: dec),
                                      if (widget.isCharging &&
                                          widget.height >= 16)
                                        Center(
                                          child: Icon(
                                            Icons.bolt,
                                            size: widget.height * 0.7,
                                            color: Colors.white,
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                      ),
                    );
                  },
                ),
              ),
              Container(
                width: nubWidth,
                height: nubHeight,
                margin: const EdgeInsets.only(left: 1),
                decoration: BoxDecoration(
                  color: context.colors.line,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(2),
                    bottomRight: Radius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        ));
  }
}
