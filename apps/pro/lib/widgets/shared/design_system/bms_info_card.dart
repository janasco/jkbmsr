import 'package:flutter/material.dart';

import 'colors.dart';
import 'tokens.dart';
import 'typography.dart';
import '../../../models/telemetry.dart';

/// Battery/BMS information panel — a compact label/value list (pack flow,
/// capacity, cycles, state of health, cell delta, balancing). Mirrored from
/// the jkbmsr-ble redesign's BmsInfoSection so both apps share one vocabulary.
/// Every value comes from the decoded [Telemetry]; when there's no telemetry
/// yet the rows show "—" rather than zeros.
class JKBMSRBmsInfoCard extends StatelessWidget {
  final Telemetry? telemetry;

  const JKBMSRBmsInfoCard({Key? key, required this.telemetry}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = telemetry;
    final bms = t?.bms;

    final rows = <(String, String)>[
      ('Pack voltage', t != null ? '${t.voltage.toStringAsFixed(2)} V' : '—'),
      ('Current', t != null ? '${t.current.toStringAsFixed(1)} A' : '—'),
      ('Power', t != null ? '${t.power.toStringAsFixed(0)} W' : '—'),
      ('Remaining capacity', bms != null ? '${bms.remainingCapacityAh.toStringAsFixed(1)} Ah' : '—'),
      ('Full capacity', bms != null ? '${bms.fullCapacityAh.toStringAsFixed(1)} Ah' : '—'),
      ('Cycle count', bms != null ? '${bms.cycleCount}' : '—'),
      (
        'State of health',
        (bms?.stateOfHealth != null) ? '${bms!.stateOfHealth!.toStringAsFixed(0)} %' : '—',
      ),
      ('Cell delta', bms != null ? '${bms.deltaCellVoltage.toStringAsFixed(0)} mV' : '—'),
      ('Balancing', bms != null ? (bms.balancing ? 'Active' : 'Idle') : '—'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Battery & BMS info',
          style: JKBMSRTypography.sectionHeading.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: JKBMSRTokens.space8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: JKBMSRTokens.space16, vertical: 4),
          decoration: BoxDecoration(
            color: colors.panel,
            borderRadius: BorderRadius.circular(JKBMSRTokens.radius16),
            border: Border.all(color: colors.line),
          ),
          child: Column(
            children: [
              for (int i = 0; i < rows.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        rows[i].$1,
                        style: TextStyle(fontSize: 12.5, color: colors.textMuted),
                      ),
                      const SizedBox(width: JKBMSRTokens.space12),
                      Flexible(
                        child: Text(
                          rows[i].$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: JKBMSRTypography.monoTechnical
                              .copyWith(fontSize: 12.5, color: colors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
                if (i != rows.length - 1)
                  Divider(height: 1, thickness: 1, color: colors.line.withValues(alpha: 0.6)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
