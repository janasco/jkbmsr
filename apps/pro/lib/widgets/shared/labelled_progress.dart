import 'package:flutter/material.dart';

import 'design_system/colors.dart';
import 'design_system/tokens.dart';

/// A wait that says what it is waiting for.
///
/// A bare spinner is indistinguishable from a stuck one, and on a monitoring
/// app the difference matters: "Reading the latest values" tells an owner the
/// data is on its way, while an anonymous circle invites them to reload and
/// blame the gateway.
class LabelledProgress extends StatelessWidget {
  const LabelledProgress({
    super.key,
    required this.label,
    this.compact = false,
  });

  final String label;

  /// Row layout for inside a card or a button row; column for a full screen.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<JKBMSRColors>()!;
    final indicator = SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: colors.accent),
    );
    final text = Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colors.textMuted,
          ),
    );

    if (compact) {
      return Row(
        children: [
          indicator,
          const SizedBox(width: JKBMSRTokens.space8),
          Expanded(child: text),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        indicator,
        const SizedBox(height: JKBMSRTokens.space12),
        text,
      ],
    );
  }
}
