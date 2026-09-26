import 'package:flutter/material.dart';
import 'template_shared.dart';
import '../colors.dart';
import '../tokens.dart';
import '../typography.dart';
import '../cell_voltage_grid.dart';
import '../../../../models/telemetry.dart';

/// A desktop-oriented "at a glance" layout (status | electricals | cells |
/// thermal side by side) — jkbmsr-web collapses this to a single column
/// below its `lg` breakpoint, which is what this port always renders,
/// since a phone screen never has room for four columns. Ported from
/// jkbmsr-web's AtAGlanceStripTemplate.
class JKBMSRAtAGlanceStripTemplate extends StatelessWidget {
  final Telemetry? telemetry;
  final String deviceName;
  final String deviceStatus;
  final String lastSeen;
  final bool animationsEnabled;

  const JKBMSRAtAGlanceStripTemplate({
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
    final online = deviceStatus.toLowerCase() == 'online';
    final stateOfHealth = bms?.stateOfHealth;

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
          _column(
            context,
            'STATUS',
            [
              Text(deviceName, maxLines: 1, overflow: TextOverflow.ellipsis, style: JKBMSRTypography.body.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: JKBMSRTokens.space8),
              Wrap(
                spacing: JKBMSRTokens.space8,
                runSpacing: JKBMSRTokens.space8,
                children: [
                  TemplateBadge(label: online ? 'Online' : 'Offline', tone: online ? TemplateBadgeTone.positive : TemplateBadgeTone.muted),
                  TemplateBadge(label: hasError ? 'Error' : 'OK', tone: hasError ? TemplateBadgeTone.critical : TemplateBadgeTone.positive),
                ],
              ),
              const SizedBox(height: JKBMSRTokens.space8),
              Wrap(
                spacing: JKBMSRTokens.space8,
                runSpacing: JKBMSRTokens.space8,
                children: [
                  TemplateBadge(label: charging ? 'Charging' : 'Not charging', tone: charging ? TemplateBadgeTone.positive : TemplateBadgeTone.muted),
                  TemplateBadge(label: discharging ? 'Discharging' : 'Not discharging', tone: discharging ? TemplateBadgeTone.positive : TemplateBadgeTone.muted),
                  TemplateBadge(label: (bms?.balancing ?? false) ? 'Balancing' : 'Idle', tone: (bms?.balancing ?? false) ? TemplateBadgeTone.positive : TemplateBadgeTone.muted),
                ],
              ),
              const SizedBox(height: JKBMSRTokens.space8),
              Text('Last update: $lastSeen', style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted)),
            ],
          ),
          const SizedBox(height: JKBMSRTokens.space12),
          _column(
            context,
            'ELECTRICALS',
            [
              Row(
                children: [
                  Expanded(child: _bigStat(context, Icons.bolt, 'Voltage', '${(t?.voltage ?? 0.0).toStringAsFixed(2)} V')),
                  Expanded(child: _bigStat(context, Icons.swap_horiz, 'Current', '${current.toStringAsFixed(2)} A')),
                ],
              ),
              const SizedBox(height: JKBMSRTokens.space12),
              Row(
                children: [
                  Expanded(child: _bigStat(context, Icons.flash_on, 'Power', '${(t?.power ?? 0.0).toStringAsFixed(0)} W')),
                  Expanded(child: _bigStat(context, Icons.battery_charging_full, 'SoC', '${(t?.soc ?? 0.0).toStringAsFixed(0)}%')),
                ],
              ),
              const SizedBox(height: JKBMSRTokens.space12),
              _bigStat(context, Icons.favorite, 'SoH', stateOfHealth != null ? '${stateOfHealth.toStringAsFixed(0)}%' : '—'),
            ],
          ),
          const SizedBox(height: JKBMSRTokens.space12),
          _column(
            context,
            'CELLS',
            [
              TemplateDetailPanel(
                items: [
                  TemplateDetailItem(icon: Icons.power, label: 'Avg Voltage', value: '${(bms?.avgCellVoltage ?? 0.0).toStringAsFixed(3)} V'),
                  TemplateDetailItem(icon: Icons.arrow_downward, label: 'Min Voltage', value: '${(bms?.minCellVoltage ?? 0.0).toStringAsFixed(3)} V'),
                  TemplateDetailItem(icon: Icons.arrow_upward, label: 'Max Voltage', value: '${(bms?.maxCellVoltage ?? 0.0).toStringAsFixed(3)} V'),
                  TemplateDetailItem(icon: Icons.trending_down, label: 'Delta', value: '${((bms?.deltaCellVoltage ?? 0.0) * 1000).toStringAsFixed(0)} mV'),
                  TemplateDetailItem(icon: Icons.autorenew, label: 'Cycle Count', value: '${bms?.cycleCount ?? 0}'),
                  TemplateDetailItem(icon: Icons.battery_full, label: 'Remaining', value: '${(bms?.remainingCapacityAh ?? 0.0).toStringAsFixed(1)} Ah'),
                ],
              ),
            ],
          ),
          const SizedBox(height: JKBMSRTokens.space12),
          _column(
            context,
            'THERMAL',
            [
              Row(
                children: [
                  Expanded(child: _bigStat(context, Icons.thermostat, 'Battery T1', '${(t?.temperature1 ?? 0.0).toStringAsFixed(1)} °C')),
                  Expanded(child: _bigStat(context, Icons.device_thermostat, 'Battery T2', '${(t?.temperature2 ?? 0.0).toStringAsFixed(1)} °C')),
                ],
              ),
              const SizedBox(height: JKBMSRTokens.space12),
              TemplateDetailPanel(
                items: [
                  TemplateDetailItem(icon: Icons.memory, label: 'MOSFET Temp', value: '${(bms?.mosfetTemperature ?? 0.0).toStringAsFixed(1)} °C'),
                  TemplateDetailItem(icon: Icons.compare_arrows, label: 'Balance Curr.', value: '${(bms?.balancingCurrent ?? 0.0).toStringAsFixed(2)} A'),
                ],
              ),
            ],
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

  Widget _bigStat(BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: JKBMSRTokens.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: context.colors.accent),
          const SizedBox(width: JKBMSRTokens.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: JKBMSRTypography.label.copyWith(color: context.colors.textSubtle, fontSize: 11.0)),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: JKBMSRTypography.body.copyWith(color: context.colors.accent, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _column(BuildContext context, String title, List<Widget> children) {
    return _tile(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: JKBMSRTokens.space12),
          ...children,
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
