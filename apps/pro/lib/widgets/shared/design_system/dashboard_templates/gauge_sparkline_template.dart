import 'package:flutter/material.dart';
import 'template_shared.dart';
import '../colors.dart';
import '../tokens.dart';
import '../typography.dart';
import '../cell_voltage_grid.dart';
import '../../../../models/telemetry.dart';
import '../../../../models/telemetry_history_point.dart';

/// Gauge-focused dashboard layout — same real data as the default/classic
/// readouts, but the headline voltage/remaining-capacity are shown as a
/// filled trend sparkline and a semicircle gauge instead of plain numbers.
/// Ported from jkbmsr-web's GaugeSparklineTemplate.
class JKBMSRGaugeSparklineTemplate extends StatelessWidget {
  final Telemetry? telemetry;
  final String lastSeen;
  final bool animationsEnabled;
  final List<TelemetryHistoryPoint> history;

  const JKBMSRGaugeSparklineTemplate({
    Key? key,
    required this.telemetry,
    required this.lastSeen,
    required this.history,
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
    final socColor = soc < 20 ? context.colors.critical : soc < 50 ? context.colors.warning : context.colors.accent;
    final voltageHistory = history.map((point) => point.voltage).toList();

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _tile(
                  context,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('VOLTAGE', style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted)),
                      const SizedBox(height: JKBMSRTokens.space4),
                      Text(
                        '${(t?.voltage ?? 0.0).toStringAsFixed(3)} V',
                        maxLines: 1,
                        style: JKBMSRTypography.sectionHeading.copyWith(color: context.colors.accent),
                      ),
                      const SizedBox(height: JKBMSRTokens.space8),
                      TemplateSparkline(values: voltageHistory, color: context.colors.accent),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: JKBMSRTokens.space12),
              Expanded(
                child: _tile(
                  context,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('REMAINING CAPACITY', maxLines: 1, overflow: TextOverflow.ellipsis, style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted)),
                      TemplateGauge(
                        percent: soc / 100,
                        valueLabel: '${(bms?.remainingCapacityAh ?? 0.0).toStringAsFixed(1)} Ah',
                        subLabel: '${soc.round()}% remaining',
                        color: socColor,
                      ),
                    ],
                  ),
                ),
              ),
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
                TemplateDetailItem(icon: Icons.flash_on, label: 'Power Draw', value: '${(t?.power ?? 0.0).toStringAsFixed(0)} W'),
                TemplateDetailItem(icon: Icons.swap_horiz, label: 'Current', value: '${current.toStringAsFixed(2)} A'),
                TemplateDetailItem(icon: Icons.inventory_2, label: 'Total Capacity', value: '${(bms?.fullCapacityAh ?? 0.0).toStringAsFixed(1)} Ah'),
                TemplateDetailItem(icon: Icons.repeat, label: 'Cycle Capacity', value: '${(bms?.cycleCapacityAh ?? 0.0).toStringAsFixed(2)} Ah'),
                TemplateDetailItem(icon: Icons.autorenew, label: 'Cycle Count', value: '${bms?.cycleCount ?? 0}'),
                TemplateDetailItem(icon: Icons.power, label: 'Avg Cell V', value: '${(bms?.avgCellVoltage ?? 0.0).toStringAsFixed(2)} V'),
                TemplateDetailItem(icon: Icons.trending_down, label: 'Delta Cell V', value: '${(bms?.deltaCellVoltage ?? 0.0).toStringAsFixed(2)} V'),
                TemplateDetailItem(icon: Icons.compare_arrows, label: 'Balance Curr', value: '${(bms?.balancingCurrent ?? 0.0).toStringAsFixed(2)} A'),
                TemplateDetailItem(icon: Icons.thermostat, label: 'Battery T1', value: '${(t?.temperature1 ?? 0.0).toStringAsFixed(1)} °C'),
                TemplateDetailItem(icon: Icons.device_thermostat, label: 'Battery T2', value: '${(t?.temperature2 ?? 0.0).toStringAsFixed(1)} °C'),
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

  Widget _tile(BuildContext context, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(JKBMSRTokens.space16),
      decoration: BoxDecoration(color: context.colors.panel, borderRadius: BorderRadius.circular(JKBMSRTokens.radius8), border: Border.all(color: context.colors.line)),
      child: child,
    );
  }
}
