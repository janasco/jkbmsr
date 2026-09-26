import 'package:flutter/material.dart';
import 'template_shared.dart';
import '../colors.dart';
import '../tokens.dart';
import '../typography.dart';
import '../cell_voltage_grid.dart';
import '../../../../models/telemetry.dart';

/// SoC as the hero, via a red/yellow/blue danger-zone gauge instead of a
/// flat single-tone fill — flags low charge at a glance rather than making
/// you read the number. Everything below the gauge is the same real data
/// as the other templates. Ported from jkbmsr-web's SeverityGaugeTemplate.
class JKBMSRSeverityGaugeTemplate extends StatelessWidget {
  final Telemetry? telemetry;
  final String lastSeen;
  final bool animationsEnabled;

  const JKBMSRSeverityGaugeTemplate({
    Key? key,
    required this.telemetry,
    required this.lastSeen,
    this.animationsEnabled = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final t = telemetry;
    final bms = t?.bms;
    final current = t?.current ?? 0.0;
    final charging = current > 0.05;
    final discharging = current < -0.05;
    final soc = (t?.soc ?? 0.0).clamp(0.0, 100.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(JKBMSRTokens.space16),
      decoration: BoxDecoration(
        color: context.colors.inset,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
        border: Border.all(color: context.colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tile(
            context,
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TemplateSeverityGauge(
                  percent: soc / 100,
                  valueLabel: '${soc.round()}%',
                  subLabel: '${(bms?.remainingCapacityAh ?? 0.0).toStringAsFixed(1)} Ah remaining',
                ),
                const SizedBox(height: JKBMSRTokens.space12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: JKBMSRTokens.space16,
                  runSpacing: JKBMSRTokens.space8,
                  children: [
                    _legendDot(context, context.colors.critical, 'Below 20%'),
                    _legendDot(context, context.colors.warning, 'Below 50%'),
                    _legendDot(context, context.colors.signal, '50% and up'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: JKBMSRTokens.space16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _tile(context, TemplateStatCard(icon: Icons.bolt, label: 'VOLTAGE', value: '${(t?.voltage ?? 0.0).toStringAsFixed(2)} V'))),
              const SizedBox(width: JKBMSRTokens.space8),
              Expanded(child: _tile(context, TemplateStatCard(icon: Icons.swap_horiz, label: 'CURRENT', value: '${current.toStringAsFixed(2)} A'))),
              const SizedBox(width: JKBMSRTokens.space8),
              Expanded(child: _tile(context, TemplateStatCard(icon: Icons.flash_on, label: 'POWER', value: '${(t?.power ?? 0.0).toStringAsFixed(0)} W'))),
            ],
          ),
          const SizedBox(height: JKBMSRTokens.space16),
          _tile(context, TemplateStatusRow(lastSeen: lastSeen, bms: t?.bms ?? BmsExtras.fromJson(null))),
          const SizedBox(height: JKBMSRTokens.space16),
          _tile(
            context,
            TemplateDetailPanel(
              title: 'PACK DETAILS',
              items: [
                TemplateDetailItem(icon: Icons.inventory_2, label: 'Total Capacity', value: '${(bms?.fullCapacityAh ?? 0.0).toStringAsFixed(0)} Ah'),
                TemplateDetailItem(icon: Icons.repeat, label: 'Cycle Capacity', value: '${(bms?.cycleCapacityAh ?? 0.0).toStringAsFixed(1)} Ah'),
                TemplateDetailItem(icon: Icons.autorenew, label: 'Cycle Count', value: '${bms?.cycleCount ?? 0}'),
                TemplateDetailItem(icon: Icons.power, label: 'Avg Cell V', value: '${(bms?.avgCellVoltage ?? 0.0).toStringAsFixed(3)} V'),
                TemplateDetailItem(icon: Icons.trending_down, label: 'Delta Cell V', value: '${((bms?.deltaCellVoltage ?? 0.0) * 1000).toStringAsFixed(0)} mV'),
                TemplateDetailItem(icon: Icons.compare_arrows, label: 'Balance Curr', value: '${(bms?.balancingCurrent ?? 0.0).toStringAsFixed(2)} A'),
                TemplateDetailItem(icon: Icons.thermostat, label: 'Battery T1', value: '${(t?.temperature1 ?? 0.0).toStringAsFixed(1)} °C'),
                TemplateDetailItem(icon: Icons.memory, label: 'MOS Temp', value: '${(bms?.mosfetTemperature ?? 0.0).toStringAsFixed(1)} °C'),
              ],
            ),
          ),
          const SizedBox(height: JKBMSRTokens.space16),
          _tile(
            context,
            JKBMSRCellVoltageGrid(
              cells: t?.cells ?? const [],
              isCharging: charging,
              isDischarging: discharging,
              animationsEnabled: animationsEnabled,
            ),
          ),
          const SizedBox(height: JKBMSRTokens.space16),
          _tile(context, TemplateSwitchesPanel(bms: t?.bms ?? BmsExtras.fromJson(null))),
        ],
      ),
    );
  }

  Widget _legendDot(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: JKBMSRTokens.space4),
        Text(label, style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted)),
      ],
    );
  }

  Widget _tile(BuildContext context, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(JKBMSRTokens.space16),
      decoration: BoxDecoration(color: context.colors.panel, borderRadius: BorderRadius.circular(JKBMSRTokens.radius8), border: Border.all(color: context.colors.line)),
      child: child,
    );
  }
}
