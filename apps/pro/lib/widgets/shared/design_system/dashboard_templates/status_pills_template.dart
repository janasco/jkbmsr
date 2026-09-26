import 'package:flutter/material.dart';
import 'template_shared.dart';
import '../colors.dart';
import '../tokens.dart';
import '../typography.dart';
import '../cell_voltage_grid.dart';
import '../../../../models/telemetry.dart';

/// Status-focused dashboard layout: a top row of connectivity/error/balancing
/// pills, voltage/current/power headline cards, and SoC/SoH shown side by
/// side. Ported from jkbmsr-web's StatusPillsTemplate. The reference this
/// was inspired by also has a charge-stage pill ("Bulk"/"Absorption"/
/// "Float") and an uptime counter, and two editable capacity/voltage
/// fields — this system doesn't classify charge stages, track BMS boot
/// time, or have a remote-write path for those settings, so none of that
/// is faked here.
class JKBMSRStatusPillsTemplate extends StatelessWidget {
  final Telemetry? telemetry;
  final String deviceName;
  final String deviceStatus;
  final String lastSeen;
  final bool animationsEnabled;

  const JKBMSRStatusPillsTemplate({
    Key? key,
    required this.telemetry,
    required this.deviceName,
    required this.deviceStatus,
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
    final hasError = (bms?.errorsBitmask ?? 0) != 0;
    final temps = [t?.temperature1 ?? 0.0, t?.temperature2 ?? 0.0, bms?.mosfetTemperature ?? 0.0];
    final minTemp = temps.reduce((a, b) => a < b ? a : b);
    final maxTemp = temps.reduce((a, b) => a > b ? a : b);
    final powerState = charging ? 'Charging' : discharging ? 'Discharging' : 'Idle';
    final online = deviceStatus.toLowerCase() == 'online';
    final stateOfHealth = bms?.stateOfHealth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tile(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(deviceName, maxLines: 1, overflow: TextOverflow.ellipsis, style: JKBMSRTypography.body.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: JKBMSRTokens.space8),
              Wrap(
                spacing: JKBMSRTokens.space8,
                runSpacing: JKBMSRTokens.space8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TemplateBadge(label: online ? 'Online' : 'Offline', tone: online ? TemplateBadgeTone.positive : TemplateBadgeTone.muted),
                  TemplateBadge(label: hasError ? 'Error' : 'OK', tone: hasError ? TemplateBadgeTone.critical : TemplateBadgeTone.positive),
                  TemplateBadge(label: (bms?.balancing ?? false) ? 'Balancing' : 'Idle', tone: (bms?.balancing ?? false) ? TemplateBadgeTone.positive : TemplateBadgeTone.muted),
                  Text('Last seen: $lastSeen', style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: JKBMSRTokens.space16),
        TemplateStatusRow(lastSeen: lastSeen, bms: t?.bms ?? BmsExtras.fromJson(null)),
        const SizedBox(height: JKBMSRTokens.space16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _tile(context, TemplateStatCard(icon: Icons.bolt, label: 'VOLTAGE', value: '${(t?.voltage ?? 0.0).toStringAsFixed(3)} V'))),
            const SizedBox(width: JKBMSRTokens.space8),
            Expanded(child: _tile(context, TemplateStatCard(icon: Icons.swap_horiz, label: 'CURRENT', value: '${current.toStringAsFixed(2)} A'))),
            const SizedBox(width: JKBMSRTokens.space8),
            Expanded(child: _tile(context, TemplateStatCard(icon: Icons.flash_on, label: 'POWER', value: '${(t?.power ?? 0.0).toStringAsFixed(1)} W', sub: powerState))),
          ],
        ),
        const SizedBox(height: JKBMSRTokens.space12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _tile(context, TemplateStatCard(icon: Icons.battery_charging_full, label: 'SOC', value: '${(t?.soc ?? 0.0).toStringAsFixed(2)}%'))),
            const SizedBox(width: JKBMSRTokens.space8),
            Expanded(child: _tile(context, TemplateStatCard(icon: Icons.favorite, label: 'SOH', value: stateOfHealth != null ? '${stateOfHealth.toStringAsFixed(2)}%' : '—'))),
          ],
        ),
        const SizedBox(height: JKBMSRTokens.space16),
        _tile(
          context,
          TemplateDetailPanel(
            title: 'PACK DETAILS',
            items: [
              TemplateDetailItem(icon: Icons.inventory_2, label: 'Battery Cap', value: '${(bms?.fullCapacityAh ?? 0.0).toStringAsFixed(0)} Ah'),
              TemplateDetailItem(icon: Icons.battery_full, label: 'Remain Cap', value: '${(bms?.remainingCapacityAh ?? 0.0).toStringAsFixed(2)} Ah'),
              TemplateDetailItem(icon: Icons.power, label: 'Ave Cell Vol', value: '${(bms?.avgCellVoltage ?? 0.0).toStringAsFixed(3)} V'),
              TemplateDetailItem(icon: Icons.trending_down, label: 'Delta Cell Vol', value: '${(bms?.deltaCellVoltage ?? 0.0).toStringAsFixed(3)} V'),
              TemplateDetailItem(icon: Icons.compare_arrows, label: 'Balance Cur', value: '${(bms?.balancingCurrent ?? 0.0).toStringAsFixed(2)} A'),
              TemplateDetailItem(icon: Icons.autorenew, label: 'Cycle', value: '${bms?.cycleCount ?? 0}'),
              TemplateDetailItem(icon: Icons.thermostat, label: 'Min Temp', value: '${minTemp.toStringAsFixed(1)} °C'),
              TemplateDetailItem(icon: Icons.device_thermostat, label: 'Max Temp', value: '${maxTemp.toStringAsFixed(1)} °C'),
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
