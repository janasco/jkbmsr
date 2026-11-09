import 'package:flutter/material.dart';

import '../../../widgets/shared/design_system/colors.dart';
import '../../../widgets/shared/design_system/tokens.dart';
import '../../../widgets/shared/design_system/typography.dart';

/// A named line of work for the battery dashboard.
///
/// The dashboard's loading and refresh paths are requests, not stages: the
/// caller passes the label for the request it is actually waiting on, and
/// this widget renders it verbatim. Nothing here sequences phases, measures
/// progress or advances on a timer, so it cannot claim work the screen has
/// not started.
///
/// [compact] is the quieter treatment for a refresh over content that is
/// already on screen: smaller type, a muted colour and no accent ring
/// competing with the live readings.
class DashboardActivityStatus extends StatelessWidget {
  final String label;
  final bool compact;

  const DashboardActivityStatus({
    Key? key,
    required this.label,
    this.compact = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // The design system's skeleton stops pulsing when the OS asks for
    // reduced motion; the ring follows the same rule instead of animating
    // regardless.
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final color = compact ? context.colors.textMuted : context.colors.textSecondary;
    final diameter = compact ? 10.0 : 14.0;
    final ringColor = compact ? color : context.colors.accent;

    final style = (compact
            ? JKBMSRTypography.label
            : JKBMSRTypography.bodySecondary)
        .copyWith(color: color);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: diameter,
          height: diameter,
          child: reduceMotion
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: ringColor,
                    shape: BoxShape.circle,
                  ),
                )
              : CircularProgressIndicator(
                  strokeWidth: compact ? 1.5 : 2.0,
                  color: ringColor,
                ),
        ),
        SizedBox(
          width: compact ? JKBMSRTokens.space8 : JKBMSRTokens.space12,
        ),
        Flexible(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}
