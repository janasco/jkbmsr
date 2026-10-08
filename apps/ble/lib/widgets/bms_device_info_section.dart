import 'package:flutter/material.dart';

import '../models/bms_parameter.dart';

/// Hardware-identity card decoded from the JK-BMS device-info frame
/// (JK02 frame type 0x03). This is a different surface from
/// [BmsInfoSection]: that one reports *live battery* state, this one reports
/// the *hardware itself* — model, hardware/firmware revision, serial number,
/// manufacturing date, power-on count and total run time.
///
/// Every value comes straight from [BmsModelInfo]; when nothing has been
/// decoded yet (or a field is absent from the frame) the row shows "—"
/// rather than a placeholder that could be mistaken for a real reading.
class BmsDeviceInfoSection extends StatelessWidget {
  final BmsModelInfo? info;
  final bool isConnected;

  const BmsDeviceInfoSection({
    super.key,
    required this.info,
    required this.isConnected,
  });

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

    final i = info;
    final rows = <(String, String)>[
      ('Model', _orDash(i?.modelName)),
      ('Hardware version', _orDash(i?.hardwareVersion)),
      ('Firmware version', _orDash(i?.softwareVersion)),
      ('Serial number', _orDash(i?.serialNumber)),
      ('Manufactured', _orDash(i?.manufacturingDate)),
      ('Power-on count', i == null ? '—' : '${i.powerOnCount}'),
      ('Total run time', i == null ? '—' : _fmtDuration(i.uptimeSeconds)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Device information',
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
              for (int r = 0; r < rows.length; r++) ...[
                _InfoRow(
                  label: rows[r].$1,
                  value: isConnected ? rows[r].$2 : '—',
                  textPrimary: textPrimary,
                ),
                if (r != rows.length - 1)
                  Divider(height: 1, thickness: 1, color: borderColor.withValues(alpha: 0.6)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _orDash(String? v) => (v == null || v.isEmpty) ? '—' : v;
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
          Text(label, style: const TextStyle(fontSize: 12.5, color: BmsDeviceInfoSection._muted)),
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
