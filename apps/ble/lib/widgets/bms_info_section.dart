import 'package:flutter/material.dart';

import '../models/bms_models.dart';

/// "Battery / BMS information" card — a compact label/value panel (model,
/// brand, chemistry, capacity, cycles, cell count, balancing, sleep timer),
/// adopted from the reference info screens. Values come straight from the
/// decoded [BmsStatus]; when offline every value shows "—".
class BmsInfoSection extends StatelessWidget {
  final BmsStatus status;
  final bool isConnected;

  const BmsInfoSection({super.key, required this.status, required this.isConnected});

  static const _muted = Color(0xFF64748B);

  static String _fmtDuration(int seconds) {
    if (seconds <= 0) return '—';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF131A20) : const Color(0xFFFFFFFF);
    final borderColor = isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

    final rows = <(String, String)>[
      ('Model', status.modelName),
      ('Brand', status.brand.name.toUpperCase()),
      ('Chemistry', status.cellType),
      ('Nominal capacity', '${status.nominalCapacityAh.toStringAsFixed(1)} Ah'),
      ('Remaining capacity', '${status.remainingCapacityAh.toStringAsFixed(1)} Ah'),
      ('Cycle count', '${status.cycleCount}'),
      ('Active cells', '${status.cells.length}'),
      ('Balance current', '${status.balanceCurrentA.toStringAsFixed(1)} A'),
      ('Sleep timer', _fmtDuration(status.timeEnterSleepSec)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Battery & BMS info',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            children: [
              for (int i = 0; i < rows.length; i++) ...[
                _InfoRow(
                  label: rows[i].$1,
                  value: isConnected ? rows[i].$2 : '—',
                  textPrimary: textPrimary,
                ),
                if (i != rows.length - 1)
                  Divider(height: 1, thickness: 1, color: borderColor.withValues(alpha: 0.6)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color textPrimary;

  const _InfoRow({required this.label, required this.value, required this.textPrimary});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: BmsInfoSection._muted)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: textPrimary, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
