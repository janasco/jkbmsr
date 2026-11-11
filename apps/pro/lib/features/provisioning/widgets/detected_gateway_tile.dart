import 'package:flutter/material.dart';

import '../../../widgets/shared/design_system/colors.dart';
import '../../../widgets/shared/design_system/tokens.dart';
import '../discovered_gateway.dart';

/// A detected gateway, floating over the radar.
///
/// It enters with a short scale-and-fade so a gateway appearing reads as an
/// event rather than a row that was always there, and the whole card is the tap
/// target: the instruction is "tap the gateway", not "tap a small button next to
/// it".
class DetectedGatewayTile extends StatelessWidget {
  const DetectedGatewayTile({
    super.key,
    required this.gateway,
    required this.onTap,
  });

  final DiscoveredGateway gateway;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<JKBMSRColors>()!;
    final text = Theme.of(context).textTheme;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.scale(
          scale: 0.96 + 0.04 * value,
          child: child,
        ),
      ),
      child: Material(
        color: colors.panel,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius16),
        child: InkWell(
          borderRadius: BorderRadius.circular(JKBMSRTokens.radius16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: JKBMSRTokens.space16,
              vertical: JKBMSRTokens.space12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(JKBMSRTokens.radius16),
              border: Border.all(color: colors.accent.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
                  ),
                  child: Icon(Icons.router_outlined, color: colors.accent),
                ),
                const SizedBox(width: JKBMSRTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gateway ${gateway.shortCode}',
                        style: text.titleMedium?.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: JKBMSRTokens.space2),
                      Text(
                        'Tap to set up',
                        style: text.bodySmall?.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                _SignalBars(bars: gateway.signalBars, color: colors.accent),
                const SizedBox(width: JKBMSRTokens.space8),
                Icon(
                  Icons.chevron_right,
                  color: colors.textSubtle,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.bars, required this.color});

  final int bars;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Signal $bars of 3',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (i) {
          final on = i < bars;
          return Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Container(
              width: 3,
              height: 6.0 + i * 4,
              decoration: BoxDecoration(
                color: on ? color : color.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          );
        }),
      ),
    );
  }
}
