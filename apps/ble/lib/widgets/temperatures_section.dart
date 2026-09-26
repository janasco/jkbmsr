import 'package:flutter/material.dart';
import '../models/bms_models.dart';
import 'motion_kit.dart';

class TemperaturesSection extends StatelessWidget {
  final BmsStatus status;
  final bool isConnected;
  const TemperaturesSection({super.key, required this.status, required this.isConnected});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF131A20) : const Color(0xFFFFFFFF);
    final iconBg = isDark ? const Color(0xFF1E2830).withValues(alpha: 0.5) : const Color(0xFFF1F5F9);
    final borderColor = isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final mutedText = const Color(0xFF64748B);

    final temps = [
      _TempData(label: 'MOS', temp: isConnected ? '${status.mosTemp.toStringAsFixed(1)} °C' : '—', icon: Icons.memory_rounded),
      _TempData(
          label: 'Battery T1', temp: isConnected ? '${status.t1Temp.toStringAsFixed(1)} °C' : '—', icon: Icons.device_thermostat_rounded),
      _TempData(
          label: 'Battery T2', temp: isConnected ? '${status.t2Temp.toStringAsFixed(1)} °C' : '—', icon: Icons.device_thermostat_rounded),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Temperatures',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
        ),
        const SizedBox(height: 8),
        Row(
          children: temps.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TileEntrance(
                  delayIndex: index,
                  child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isConnected ? cardBg : cardBg.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: iconBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.device_thermostat_rounded, color: Color(0xFF64748B), size: 18),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.label,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.temp,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: isConnected ? textPrimary : mutedText,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _TempData {
  final String label;
  final String temp;
  final IconData icon;

  _TempData({
    required this.label,
    required this.temp,
    required this.icon,
  });
}
