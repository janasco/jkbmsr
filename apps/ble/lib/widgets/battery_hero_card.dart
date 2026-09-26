import 'package:flutter/material.dart';
import '../models/bms_models.dart';
import 'motion_kit.dart';
import 'soc_ring.dart';

/// The primary "at a glance" summary for the connected BMS: a live
/// charge/discharge badge, an animated SOC banner with capacity and cycle
/// count, a 2x2 grid of headline metrics, and a cell-imbalance footer.
/// Every value here comes straight from the decoded BmsStatus — nothing
/// fabricated (unlike the old power-flow diagram this replaced, which
/// always showed a fake "450W solar / 320W load" no BMS protocol actually
/// reports).
class BatteryHeroCard extends StatelessWidget {
  final BmsStatus status;
  final bool isConnected;

  const BatteryHeroCard({super.key, required this.status, required this.isConnected});

  static const _green = Color(0xFF10B981);
  static const _blue = Color(0xFF0284C7);
  static const _skyBlue = Color(0xFF38BDF8);
  static const _amber = Color(0xFFF59E0B);
  static const _red = Color(0xFFEF4444);
  static const _muted = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF131A20) : const Color(0xFFFFFFFF);
    final borderColor = isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0);
    final insetBg = isDark ? const Color(0xFF0D1318) : const Color(0xFFF8FAFC);
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

    final soc = isConnected ? status.soc.toDouble() : 0.0;
    final socColor = !isConnected
        ? _muted
        : soc < 20
            ? _red
            : soc < 50
                ? _amber
                : _green;

    final current = status.currentA;
    final charging = isConnected && current > 0.05;
    final discharging = isConnected && current < -0.05;
    final (String statusLabel, Color statusColor, IconData statusIcon) = !isConnected
        ? ('OFFLINE', _muted, Icons.bluetooth_disabled_rounded)
        : charging
            ? ('CHARGING (${current.toStringAsFixed(1)} A)', _green, Icons.battery_charging_full_rounded)
            : discharging
                ? ('DISCHARGING (${current.toStringAsFixed(1)} A)', _skyBlue, Icons.arrow_downward_rounded)
                : ('STANDBY', _muted, Icons.battery_std_rounded);

    final maxTemp = [status.t1Temp, status.t2Temp, status.mosTemp].reduce((a, b) => a > b ? a : b);
    final tempColor = !isConnected ? _muted : (maxTemp > 50 ? _red : _blue);

    final power = status.powerW;
    final powerLabel = isConnected
        ? (power.abs() >= 1000 ? '${(power / 1000).toStringAsFixed(2)} kW' : '${power.toStringAsFixed(0)} W')
        : '—';

    final deltaMv = status.deltaVoltageMv;
    final imbalanceOk = deltaMv < 30;
    final balancingActive = isConnected && status.isBalancingActive;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: device model + live status badge.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    // Live status dot: pulses while connected, static when
                    // offline.
                    PulseDot(color: statusColor, size: 8, active: isConnected),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isConnected ? status.modelName : 'No device connected',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 14, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // SOC banner. A light sheen sweeps across it while charging —
          // energy visibly flowing into the pack.
          ChargingSheen(
            enabled: charging,
            tint: socColor,
            child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: socColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: socColor.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                SocRing(percent: soc, live: isConnected, color: socColor, size: 108),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'STATE OF CHARGE',
                        style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: _muted),
                      ),
                      const SizedBox(height: 8),
                      _SocStat(
                        icon: Icons.battery_full_rounded,
                        label: 'Capacity',
                        value: isConnected
                            ? '${status.remainingCapacityAh.toStringAsFixed(1)} / ${status.nominalCapacityAh.toStringAsFixed(1)} Ah'
                            : '— / — Ah',
                        color: socColor,
                        textPrimary: textPrimary,
                      ),
                      const SizedBox(height: 8),
                      _SocStat(
                        icon: Icons.autorenew_rounded,
                        label: 'Cycles',
                        value: isConnected ? '${status.cycleCount}' : '—',
                        color: _blue,
                        textPrimary: textPrimary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ),
          const SizedBox(height: 12),

          // 2x2 headline metric grid.
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  title: 'PACK VOLTAGE',
                  value: isConnected ? '${status.totalVoltage.toStringAsFixed(2)} V' : '—',
                  subValue: isConnected ? 'Avg: ${status.averageCellVoltage.toStringAsFixed(3)} V' : '',
                  icon: Icons.bolt_rounded,
                  accentColor: isConnected ? _blue : _muted,
                  isDark: isDark,
                  insetBg: insetBg,
                  textPrimary: textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricTile(
                  title: 'CURRENT',
                  value: isConnected ? '${current.toStringAsFixed(1)} A' : '—',
                  animValue: isConnected ? current : null,
                  formatter: (v) => '${v.toStringAsFixed(1)} A',
                  subValue: isConnected ? (charging ? 'Charging' : (discharging ? 'Discharging' : 'Standby')) : '',
                  icon: Icons.speed_rounded,
                  accentColor: !isConnected ? _muted : (charging ? _green : _skyBlue),
                  isDark: isDark,
                  insetBg: insetBg,
                  textPrimary: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  title: 'POWER',
                  value: powerLabel,
                  animValue: isConnected ? power : null,
                  formatter: (v) => v.abs() >= 1000
                      ? '${(v / 1000).toStringAsFixed(2)} kW'
                      : '${v.toStringAsFixed(0)} W',
                  subValue: isConnected ? '${power.toStringAsFixed(1)} W calc' : '',
                  icon: Icons.electric_bolt_rounded,
                  accentColor: isConnected ? _skyBlue : _muted,
                  isDark: isDark,
                  insetBg: insetBg,
                  textPrimary: textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricTile(
                  title: 'MOSFET / CELL TEMP',
                  value: isConnected ? '${status.mosTemp.toStringAsFixed(1)} °C' : '—',
                  subValue: isConnected ? 'Cells: ${status.t1Temp.toStringAsFixed(1)} / ${status.t2Temp.toStringAsFixed(1)} °C' : '',
                  icon: Icons.thermostat_rounded,
                  accentColor: tempColor,
                  isDark: isDark,
                  insetBg: insetBg,
                  textPrimary: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Cell-imbalance + active-balancing footer.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: insetBg, borderRadius: BorderRadius.circular(14)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        !isConnected
                            ? Icons.remove_circle_outline_rounded
                            : (imbalanceOk ? Icons.check_circle_rounded : Icons.warning_amber_rounded),
                        size: 18,
                        color: !isConnected ? _muted : (imbalanceOk ? _green : _amber),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isConnected ? 'Cell imbalance: $deltaMv mV' : 'Cell imbalance: —',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary),
                            ),
                            if (isConnected && status.cells.isNotEmpty)
                              Text(
                                'Min C${status.minCellIndex + 1}: ${status.minCellVoltage.toStringAsFixed(3)}V • '
                                'Max C${status.maxCellIndex + 1}: ${status.maxCellVoltage.toStringAsFixed(3)}V',
                                style: const TextStyle(fontSize: 11.0, color: _muted),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (balancingActive) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: _green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const PulseDot(color: _green, size: 6),
                        const SizedBox(width: 5),
                        Text(
                          'Balancing ${status.balanceCurrentA.toStringAsFixed(1)}A',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _green),
                        ),
                      ],
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

class _MetricTile extends StatelessWidget {
  final String title;
  final String value;
  final String subValue;
  final IconData icon;
  final Color accentColor;
  final bool isDark;
  final Color insetBg;
  final Color textPrimary;

  // When provided (and connected), the value text tweens smoothly between
  // consecutive telemetry readings instead of hard-cutting each poll.
  final double? animValue;
  final String Function(double)? formatter;

  const _MetricTile({
    required this.title,
    required this.value,
    required this.subValue,
    required this.icon,
    required this.accentColor,
    required this.isDark,
    required this.insetBg,
    required this.textPrimary,
    this.animValue,
    this.formatter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: insetBg,
        borderRadius: BorderRadius.circular(14),
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
                  style: const TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold, letterSpacing: 0.6, color: Color(0xFF64748B)),
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
          const SizedBox(height: 4),
          if (animValue != null && formatter != null)
            AnimatedNumber(
              value: animValue!,
              formatted: formatter!,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary, fontFamily: 'monospace'),
            )
          else
            Text(
              value,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary, fontFamily: 'monospace'),
            ),
          if (subValue.isNotEmpty)
            Text(
              subValue,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.0, color: Color(0xFF64748B)),
            ),
        ],
      ),
    );
  }
}

/// One label/value row beside the SOC ring (capacity, cycles).
class _SocStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color textPrimary;

  const _SocStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11.0,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: Color(0xFF64748B)),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                    fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
