import 'package:flutter/material.dart';
import 'colors.dart';
import 'tokens.dart';
import 'typography.dart';
import 'animated_counter.dart';
import '../../../models/telemetry.dart';

/// The primary "at a glance" battery card for a gateway's dashboard: an
/// animated SOC banner, a 2x2 grid of headline metrics, and a cell-imbalance
/// footer. Replaces the plain two-card SOC/current row that predated it —
/// same data, laid out with the hierarchy a battery owner actually scans for
/// first (charge level, then flow, then health).
class JKBMSRBatteryMetricsCard extends StatelessWidget {
  final Telemetry? telemetry;
  final String deviceName;

  const JKBMSRBatteryMetricsCard({Key? key, required this.telemetry, required this.deviceName}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final t = telemetry;
    final soc = t?.soc ?? 0.0;
    final socColor = soc < 20
        ? context.colors.critical
        : soc < 50
            ? context.colors.warning
            : context.colors.accent;

    final current = t?.current ?? 0.0;
    final charging = current > 0.05;
    final discharging = current < -0.05;
    final (String statusLabel, Color statusColor, IconData statusIcon) = charging
        ? ('CHARGING (${current.toStringAsFixed(1)} A)', context.colors.accent, Icons.battery_charging_full)
        : discharging
            ? ('DISCHARGING (${current.toStringAsFixed(1)} A)', context.colors.signal, Icons.arrow_downward)
            : ('STANDBY (0.0 A)', context.colors.textMuted, Icons.battery_std);

    final maxTemp = [
      t?.temperature1 ?? 0.0,
      t?.temperature2 ?? 0.0,
      t?.bms.mosfetTemperature ?? 0.0,
    ].reduce((a, b) => a > b ? a : b);
    final tempColor = maxTemp > 50 ? context.colors.critical : context.colors.accent;

    final power = t?.power ?? 0.0;

    final deltaMv = ((t?.bms.deltaCellVoltage ?? 0.0) * 1000).round();
    final imbalanceOk = deltaMv < 30;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(JKBMSRTokens.space16),
      decoration: BoxDecoration(
        color: context.colors.panel,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius16),
        border: Border.all(color: context.colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: device name + live power-state badge.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: JKBMSRTokens.space8),
                        Expanded(
                          child: Text(
                            deviceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: JKBMSRTypography.cardHeading.copyWith(color: context.colors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: JKBMSRTokens.space16 + JKBMSRTokens.space2),
                      child: Text('Live telemetry', style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: JKBMSRTokens.space8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: JKBMSRTokens.space8, vertical: JKBMSRTokens.space4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(JKBMSRTokens.radiusFull),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 14, color: statusColor),
                    const SizedBox(width: JKBMSRTokens.space4),
                    Text(
                      statusLabel,
                      style: JKBMSRTypography.label.copyWith(color: statusColor, fontSize: 11.0),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: JKBMSRTokens.space16),

          // SOC banner: headline percentage, capacity/cycle/SoH summary, animated bar.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(JKBMSRTokens.space12),
            decoration: BoxDecoration(
              color: socColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
              border: Border.all(color: socColor.withValues(alpha: 0.25)),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('STATE OF CHARGE', style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted)),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            JKBMSRAnimatedCounter(
                              value: soc,
                              decimalPlaces: 0,
                              suffix: '',
                              color: socColor,
                              style: JKBMSRTypography.pageHeading.copyWith(color: socColor, fontSize: 34.0, fontWeight: FontWeight.w800),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4, left: 2),
                              child: Text('%', style: JKBMSRTypography.sectionHeading.copyWith(color: socColor)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${(t?.bms.remainingCapacityAh ?? 0).toStringAsFixed(1)} / ${(t?.bms.fullCapacityAh ?? 0).toStringAsFixed(1)} Ah',
                          style: JKBMSRTypography.monoTechnical.copyWith(color: context.colors.textPrimary, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Cycles: ${t?.bms.cycleCount ?? 0} • SoH: ${t?.bms.stateOfHealth != null ? '${t!.bms.stateOfHealth!.toStringAsFixed(0)}%' : 'N/A'}',
                          style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted, fontWeight: FontWeight.w400),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: JKBMSRTokens.space12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(JKBMSRTokens.radiusFull),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: (soc / 100).clamp(0.0, 1.0)),
                    duration: JKBMSRTokens.durationSlow,
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 8,
                      backgroundColor: socColor.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation(socColor),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: JKBMSRTokens.space12),

          // 2x2 headline metric grid with animated counters.
          Row(
            children: [
              Expanded(
                child: _AnimatedMetricTile(
                  title: 'PACK VOLTAGE',
                  value: t?.voltage ?? 0,
                  unit: ' V',
                  subValue: 'Avg: ${(t?.bms.avgCellVoltage ?? 0).toStringAsFixed(3)} V',
                  icon: Icons.bolt,
                  accentColor: context.colors.accent,
                  decimalPlaces: 2,
                ),
              ),
              const SizedBox(width: JKBMSRTokens.space12),
              Expanded(
                child: _AnimatedMetricTile(
                  title: 'CURRENT',
                  value: current,
                  unit: ' A',
                  subValue: charging ? 'Charging' : (discharging ? 'Discharging' : 'Standby'),
                  icon: Icons.speed,
                  accentColor: charging ? context.colors.accent : context.colors.signal,
                  decimalPlaces: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: JKBMSRTokens.space12),
          Row(
            children: [
              Expanded(
                child: _AnimatedMetricTile(
                  title: 'POWER OUTPUT',
                  value: power,
                  unit: power.abs() >= 1000 ? ' kW' : ' W',
                  displayValue: power.abs() >= 1000 ? power / 1000 : power,
                  subValue: '${power.toStringAsFixed(1)} W calc',
                  icon: Icons.electric_bolt,
                  accentColor: context.colors.signal,
                  decimalPlaces: power.abs() >= 1000 ? 2 : 0,
                ),
              ),
              const SizedBox(width: JKBMSRTokens.space12),
              Expanded(
                child: _AnimatedMetricTile(
                  title: 'MOSFET / CELL TEMP',
                  value: t?.bms.mosfetTemperature ?? 0,
                  unit: ' °C',
                  subValue: 'Cells: ${(t?.temperature1 ?? 0).toStringAsFixed(1)} / ${(t?.temperature2 ?? 0).toStringAsFixed(1)} °C',
                  icon: Icons.thermostat,
                  accentColor: tempColor,
                  decimalPlaces: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: JKBMSRTokens.space12),

          // Cell-imbalance + active-balancing footer.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(JKBMSRTokens.space12),
            decoration: BoxDecoration(
              color: context.colors.inset,
              borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        imbalanceOk ? Icons.check_circle : Icons.warning_amber,
                        size: 18,
                        color: imbalanceOk ? context.colors.accent : context.colors.warning,
                      ),
                      const SizedBox(width: JKBMSRTokens.space8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cell imbalance: $deltaMv mV',
                              style: JKBMSRTypography.bodySecondary.copyWith(color: context.colors.textPrimary, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              'Min C${t?.bms.minVoltageCell ?? 0}: ${(t?.bms.minCellVoltage ?? 0).toStringAsFixed(3)}V • '
                              'Max C${t?.bms.maxVoltageCell ?? 0}: ${(t?.bms.maxCellVoltage ?? 0).toStringAsFixed(3)}V',
                              style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted, fontWeight: FontWeight.w400),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (t?.bms.balancing ?? false) ...[
                  const SizedBox(width: JKBMSRTokens.space8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: JKBMSRTokens.space8, vertical: JKBMSRTokens.space4),
                    decoration: BoxDecoration(
                      color: context.colors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
                    ),
                    child: Text(
                      'Balancing ${t!.bms.balancingCurrent.toStringAsFixed(1)}A',
                      style: JKBMSRTypography.label.copyWith(color: context.colors.accent, fontSize: 11.0),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A metric tile with an animated counter for the primary value.
class _AnimatedMetricTile extends StatelessWidget {
  final String title;
  final double value;
  final double? displayValue;
  final String unit;
  final String subValue;
  final IconData icon;
  final Color accentColor;
  final int decimalPlaces;

  const _AnimatedMetricTile({
    required this.title,
    required this.value,
    this.displayValue,
    required this.unit,
    required this.subValue,
    required this.icon,
    required this.accentColor,
    this.decimalPlaces = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(JKBMSRTokens.space12),
      decoration: BoxDecoration(
        color: context.colors.inset,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted, fontSize: 11.0),
                ),
              ),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(icon, size: 13, color: accentColor),
              ),
            ],
          ),
          const SizedBox(height: JKBMSRTokens.space4),
          JKBMSRAnimatedCounterCompact(
            value: displayValue ?? value,
            suffix: unit,
            decimalPlaces: decimalPlaces,
            color: context.colors.textPrimary,
            style: JKBMSRTypography.monoTechnical.copyWith(color: context.colors.textPrimary, fontSize: 17.0, fontWeight: FontWeight.w700),
          ),
          Text(
            subValue,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted, fontWeight: FontWeight.w400, fontSize: 11.0),
          ),
        ],
      ),
    );
  }
}
