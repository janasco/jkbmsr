import 'package:flutter/material.dart';

import '../../../widgets/shared/design_system/colors.dart';
import '../../../widgets/shared/design_system/tokens.dart';
import '../../../widgets/shared/design_system/typography.dart';

/// Temperature tiles in the web style: icon on top, big value, sensor label,
/// a qualitative sublabel (Cold / Normal / Warm / Hot) and a mini level bar.
/// Purely presentational — every value comes from live telemetry.
class JKBMSRTemperatureTiles extends StatelessWidget {
  final double temperature1;
  final double temperature2;
  final double mosfetTemperature;

  const JKBMSRTemperatureTiles({
    super.key,
    required this.temperature1,
    required this.temperature2,
    required this.mosfetTemperature,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.thermostat, size: 14, color: context.colors.textMuted),
            const SizedBox(width: JKBMSRTokens.space4),
            Text(
              'TEMPERATURE',
              style: JKBMSRTypography.label.copyWith(
                color: context.colors.textMuted,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: JKBMSRTokens.space8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _TempTile(
                icon: Icons.thermostat,
                value: temperature1,
                label: 'Sensor 1',
              ),
            ),
            const SizedBox(width: JKBMSRTokens.space12),
            Expanded(
              child: _TempTile(
                icon: Icons.thermostat,
                value: temperature2,
                label: 'Sensor 2',
              ),
            ),
            const SizedBox(width: JKBMSRTokens.space12),
            Expanded(
              child: _TempTile(
                icon: Icons.local_fire_department,
                value: mosfetTemperature,
                label: 'MOSFET',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _tempMood(double c) {
  if (c < 10) return 'Cold';
  if (c < 35) return 'Normal';
  if (c < 50) return 'Warm';
  return 'Hot';
}

Color _tempColor(BuildContext context, double c) {
  if (c < 10) return context.colors.signal;
  if (c < 35) return context.colors.accent;
  if (c < 50) return context.colors.warning;
  return context.colors.critical;
}

class _TempTile extends StatelessWidget {
  final IconData icon;
  final double value;
  final String label;

  const _TempTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final color = _tempColor(context, value);
    final hot = value >= 50;
    final fill = (value / 80).clamp(0.05, 1.0);
    return Container(
      padding: const EdgeInsets.all(JKBMSRTokens.space12),
      decoration: BoxDecoration(
        color: context.colors.panel,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
        border: Border.all(
          color: hot
              ? context.colors.critical.withValues(alpha: 0.5)
              : context.colors.line,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: JKBMSRTokens.space4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${value.toStringAsFixed(1)}°',
              maxLines: 1,
              style: JKBMSRTypography.monoTechnical.copyWith(
                color: color,
                fontSize: 20.0,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: JKBMSRTypography.label.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: JKBMSRTokens.space8),
          ClipRRect(
            borderRadius: BorderRadius.circular(JKBMSRTokens.radiusFull),
            child: LinearProgressIndicator(
              value: fill,
              minHeight: 4,
              backgroundColor: context.colors.control.withValues(alpha: 0.4),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: JKBMSRTokens.space4),
          Text(
            _tempMood(value),
            style: JKBMSRTypography.label.copyWith(
              color: context.colors.textMuted,
              fontSize: 10.0,
            ),
          ),
        ],
      ),
    );
  }
}
