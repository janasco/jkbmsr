import 'package:flutter/material.dart';

import '../models/bms_models.dart';
import 'motion_kit.dart';

/// "Instant Alerts" panel — surfaces the active BMS alarm flags
/// ([BmsAlarms]) as severity cards, or an all-clear state. Adopted from the
/// reference layouts; every row is driven by a real decoded flag, never a
/// fabricated value.
class AlertsSection extends StatelessWidget {
  final BmsStatus status;
  final bool isConnected;

  const AlertsSection({super.key, required this.status, required this.isConnected});

  static const _critical = Color(0xFFEF4444);
  static const _warning = Color(0xFFF59E0B);
  static const _ok = Color(0xFF10B981);
  static const _muted = Color(0xFF64748B);

  static final List<(bool Function(BmsAlarms), String, bool)> _defs = [
    ((a) => a.cellOverVoltage, 'Cell over-voltage', true),
    ((a) => a.cellUnderVoltage, 'Cell under-voltage', true),
    ((a) => a.batteryOverVoltage, 'Battery over-voltage', true),
    ((a) => a.batteryUnderVoltage, 'Battery under-voltage', false),
    ((a) => a.chargeOverCurrent, 'Charge over-current', true),
    ((a) => a.dischargeOverCurrent, 'Discharge over-current', true),
    ((a) => a.chargeOverTemp, 'Charge over-temperature', true),
    ((a) => a.chargeUnderTemp, 'Charge under-temperature', false),
    ((a) => a.dischargeOverTemp, 'Discharge over-temperature', true),
    ((a) => a.dischargeUnderTemp, 'Discharge under-temperature', false),
    ((a) => a.mosOverTemp, 'MOSFET over-temperature', true),
    ((a) => a.wireResistanceAnomaly, 'Wire resistance anomaly', false),
    ((a) => a.currentSensorAnomaly, 'Current sensor anomaly', false),
    ((a) => a.cellCountMismatch, 'Cell count mismatch', false),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF131A20) : const Color(0xFFFFFFFF);
    final borderColor = isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

    final active = _defs.where((d) => d.$1(status.alarms)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Alerts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary)),
                const Text('Active BMS alarms', style: TextStyle(fontSize: 12, color: _muted)),
              ],
            ),
            if (isConnected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (active.isEmpty ? _ok : _critical).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: (active.isEmpty ? _ok : _critical).withValues(alpha: 0.3)),
                ),
                child: Text(
                  active.isEmpty ? 'ALL CLEAR' : '${active.length} ACTIVE',
                  style: TextStyle(
                      fontSize: 11.0,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: active.isEmpty ? _ok : _critical),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (!isConnected)
          _tile(
            cardBg: cardBg,
            borderColor: borderColor,
            color: _muted,
            icon: Icons.bluetooth_disabled_rounded,
            title: 'No device connected',
            subtitle: 'Connect to a BMS to see its live alarms.',
          )
        else if (active.isEmpty)
          _tile(
            cardBg: cardBg,
            borderColor: borderColor,
            color: _ok,
            icon: Icons.verified_rounded,
            title: 'All systems normal',
            subtitle: 'No active alarms reported by the BMS.',
          )
        else
          for (int i = 0; i < active.length; i++) ...[
            _tile(
              cardBg: cardBg,
              borderColor: borderColor,
              color: active[i].$3 ? _critical : _warning,
              icon: active[i].$3 ? Icons.error_rounded : Icons.warning_amber_rounded,
              title: active[i].$2,
              subtitle: active[i].$3 ? 'Critical — address promptly' : 'Warning',
              trailing: true,
              delayIndex: i,
            ),
            if (i != active.length - 1) const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _tile({
    required Color cardBg,
    required Color borderColor,
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
    bool trailing = false,
    int delayIndex = 0,
  }) {
    return TileEntrance(
      delayIndex: delayIndex,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: color)),
                  const SizedBox(height: 1),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: _muted)),
                ],
              ),
            ),
            if (trailing)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('!',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color)),
              ),
          ],
        ),
      ),
    );
  }
}
