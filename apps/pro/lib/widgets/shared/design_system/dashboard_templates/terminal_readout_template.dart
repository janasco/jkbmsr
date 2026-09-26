import 'package:flutter/material.dart';
import 'template_shared.dart';
import '../colors.dart';
import '../tokens.dart';
import '../typography.dart';
import '../cell_voltage_grid.dart';
import '../../../../models/telemetry.dart';
import '../../../../models/telemetry_history_point.dart';

/// Monospace terminal-readout layout — combines the dense stat block from
/// the Classic Readout template with a gauge/sparkline pair, under
/// monospace styling closer to a BMS terminal readout. Ported from
/// jkbmsr-web's TerminalReadoutTemplate. Field labels are deliberately
/// worded as JKBMSR's own, and only real fields are shown — same reasoning
/// as the Classic Readout template.
class JKBMSRTerminalReadoutTemplate extends StatelessWidget {
  final Telemetry? telemetry;
  final String deviceStatus;
  final String lastSeen;
  final bool animationsEnabled;
  final List<TelemetryHistoryPoint> history;

  const JKBMSRTerminalReadoutTemplate({
    Key? key,
    required this.telemetry,
    required this.deviceStatus,
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
    final online = deviceStatus.toLowerCase() == 'online';
    final voltageHistory = history.map((point) => point.voltage).toList();
    final monoFamily = JKBMSRTypography.monoTechnical.fontFamily;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TemplateStatusRow(lastSeen: lastSeen, bms: t?.bms ?? BmsExtras.fromJson(null)),
        const SizedBox(height: JKBMSRTokens.space16),
        Row(
          children: [
            Expanded(
              child: _tile(
                context,
                TemplateStatCard(
                  icon: Icons.bolt,
                  label: 'PACK VOLTAGE',
                  value: '${(t?.voltage ?? 0.0).toStringAsFixed(2)}V',
                ),
              ),
            ),
            const SizedBox(width: JKBMSRTokens.space8),
            Expanded(
              child: _tile(
                context,
                TemplateStatCard(
                  icon: Icons.swap_horiz,
                  label: 'PACK CURRENT',
                  value: '${current.toStringAsFixed(2)}A',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: JKBMSRTokens.space16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _tile(
                context,
                TemplateGauge(
                  percent: soc / 100,
                  valueLabel: '${soc.round()}%',
                  subLabel: online ? 'STANDBY' : 'OFFLINE',
                  color: context.colors.accent,
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
                    Text('VOLTAGE TREND', maxLines: 1, overflow: TextOverflow.ellipsis, style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted, fontFamily: monoFamily)),
                    const SizedBox(height: JKBMSRTokens.space8),
                    TemplateSparkline(values: voltageHistory, color: context.colors.accent),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: JKBMSRTokens.space16),
        _tile(
          context,
          TemplateDetailPanel(
            title: 'PACK DETAILS',
            items: [
              TemplateDetailItem(icon: Icons.flash_on, label: 'Power Output', value: '${(t?.power ?? 0.0).toStringAsFixed(0)} W'),
              TemplateDetailItem(icon: Icons.battery_charging_full, label: 'State of Charge', value: '${soc.toStringAsFixed(0)} %'),
              TemplateDetailItem(icon: Icons.inventory_2, label: 'Rated Capacity', value: '${(bms?.fullCapacityAh ?? 0.0).toStringAsFixed(0)} Ah'),
              TemplateDetailItem(icon: Icons.battery_full, label: 'Remaining Capacity', value: '${(bms?.remainingCapacityAh ?? 0.0).toStringAsFixed(1)} Ah'),
              TemplateDetailItem(icon: Icons.repeat, label: 'Cycle Capacity', value: '${(bms?.cycleCapacityAh ?? 0.0).toStringAsFixed(1)} Ah'),
              TemplateDetailItem(icon: Icons.autorenew, label: 'Cycle Count', value: '${bms?.cycleCount ?? 0}'),
              TemplateDetailItem(icon: Icons.power, label: 'Avg Cell Voltage', value: '${(bms?.avgCellVoltage ?? 0.0).toStringAsFixed(3)} V'),
              TemplateDetailItem(icon: Icons.trending_down, label: 'Cell Delta', value: '${((bms?.deltaCellVoltage ?? 0.0) * 1000).toStringAsFixed(0)} mV'),
              TemplateDetailItem(icon: Icons.compare_arrows, label: 'Balance Current', value: '${(bms?.balancingCurrent ?? 0.0).toStringAsFixed(2)} A'),
              TemplateDetailItem(icon: Icons.thermostat, label: 'Temp Sensor 1', value: '${(t?.temperature1 ?? 0.0).toStringAsFixed(1)} °C'),
              TemplateDetailItem(icon: Icons.device_thermostat, label: 'Temp Sensor 2', value: '${(t?.temperature2 ?? 0.0).toStringAsFixed(1)} °C'),
              TemplateDetailItem(icon: Icons.memory, label: 'MOSFET Temp', value: '${(bms?.mosfetTemperature ?? 0.0).toStringAsFixed(1)} °C'),
            ],
          ),
        ),
        const SizedBox(height: JKBMSRTokens.space16),
        JKBMSRCellVoltageGrid(
          cells: t?.cells ?? const [],
          isCharging: charging,
          isDischarging: discharging,
          animationsEnabled: animationsEnabled,
        ),
        const SizedBox(height: JKBMSRTokens.space16),
        TemplateSwitchesPanel(bms: t?.bms ?? BmsExtras.fromJson(null)),
      ],
    );
  }

  Widget _tile(BuildContext context, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(JKBMSRTokens.space16),
      decoration: BoxDecoration(color: context.colors.inset, borderRadius: BorderRadius.circular(JKBMSRTokens.radius12)),
      child: child,
    );
  }
}
