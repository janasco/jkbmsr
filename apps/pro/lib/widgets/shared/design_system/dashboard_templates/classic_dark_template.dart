import 'package:flutter/material.dart';
import 'template_shared.dart';
import '../colors.dart';
import '../tokens.dart';
import '../cell_voltage_grid.dart';
import '../../../../models/telemetry.dart';

/// Dense terminal-style readout — one of the alternate dashboard layouts a
/// user can pick in Settings > Dashboard & Display. Ported from jkbmsr-web's
/// ClassicDarkTemplate. Only real fields are shown — no fabricated
/// per-cell wire resistance, uptime counter, or remote on/off control, and
/// field labels are JKBMSR's own rather than JK-BMS's own app's wording.
class JKBMSRClassicDarkTemplate extends StatelessWidget {
  final Telemetry? telemetry;
  final String lastSeen;
  final bool animationsEnabled;

  const JKBMSRClassicDarkTemplate({
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TemplateStatusRow(lastSeen: lastSeen, bms: t?.bms ?? BmsExtras.fromJson(null)),
        const SizedBox(height: JKBMSRTokens.space16),
        Row(
          children: [
            Expanded(
              child: TemplateStatCard(
                icon: Icons.bolt,
                label: 'VOLTAGE',
                value: '${(t?.voltage ?? 0.0).toStringAsFixed(3)} V',
              ),
            ),
            Expanded(
              child: TemplateStatCard(
                icon: Icons.swap_horiz,
                label: 'CURRENT',
                value: '${current.toStringAsFixed(2)} A',
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
              TemplateDetailItem(icon: Icons.battery_charging_full, label: 'State of Charge', value: '${(t?.soc ?? 0.0).toStringAsFixed(0)} %'),
              TemplateDetailItem(icon: Icons.inventory_2, label: 'Rated Capacity', value: '${(bms?.fullCapacityAh ?? 0.0).toStringAsFixed(0)} Ah'),
              TemplateDetailItem(icon: Icons.battery_full, label: 'Remaining Capacity', value: '${(bms?.remainingCapacityAh ?? 0.0).toStringAsFixed(0)} Ah'),
              TemplateDetailItem(icon: Icons.repeat, label: 'Cycle Capacity', value: '${(bms?.cycleCapacityAh ?? 0.0).toStringAsFixed(0)} Ah'),
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
      decoration: BoxDecoration(
        color: context.colors.inset,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
        border: Border.all(color: context.colors.line),
      ),
      child: child,
    );
  }
}
