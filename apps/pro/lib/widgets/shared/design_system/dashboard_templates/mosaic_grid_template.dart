import 'package:flutter/material.dart';
import 'template_shared.dart';
import '../colors.dart';
import '../tokens.dart';
import '../typography.dart';
import '../cell_voltage_grid.dart';
import '../../../../models/telemetry.dart';

/// Mixed-size "hero + support" grid — a wide hero voltage tile and a large
/// SoC gauge tile, smaller tiles for everything else (Icon Tiles already
/// covers the uniform-grid layout). Ported from jkbmsr-web's
/// MosaicGridTemplate.
class JKBMSRMosaicGridTemplate extends StatelessWidget {
  final Telemetry? telemetry;
  final String lastSeen;
  final bool animationsEnabled;

  const JKBMSRMosaicGridTemplate({
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
    final socColor = soc < 20 ? context.colors.critical : soc < 50 ? context.colors.warning : context.colors.accent;
    final stateOfHealth = bms?.stateOfHealth;

    // Grow the fixed grid-tile height with the OS text scale so the two text
    // lines never clip at large accessibility sizes. At the default scale
    // this is exactly 1.0, so the layout is unchanged.
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;

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
                  TemplateStatCard(
                    icon: Icons.bolt,
                    label: 'PACK VOLTAGE',
                    value: '${(t?.voltage ?? 0.0).toStringAsFixed(2)} V',
                    sub: '${(t?.power ?? 0.0).toStringAsFixed(0)} W',
                  ),
                ),
              ),
              const SizedBox(width: JKBMSRTokens.space12),
              Expanded(
                child: _tile(
                  context,
                  TemplateGauge(
                    percent: soc / 100,
                    valueLabel: '${soc.round()}%',
                    subLabel: '${(bms?.remainingCapacityAh ?? 0.0).toStringAsFixed(1)} Ah remaining',
                    color: socColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: JKBMSRTokens.space12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _tile(context, TemplateStatCard(icon: Icons.swap_horiz, label: 'CURRENT', value: '${current.toStringAsFixed(2)} A'))),
              const SizedBox(width: JKBMSRTokens.space8),
              Expanded(child: _tile(context, TemplateStatCard(icon: Icons.power, label: 'AVG CELL V', value: '${(bms?.avgCellVoltage ?? 0.0).toStringAsFixed(3)} V'))),
              const SizedBox(width: JKBMSRTokens.space8),
              Expanded(child: _tile(context, TemplateStatCard(icon: Icons.inventory_2, label: 'TOTAL CAP.', value: '${(bms?.fullCapacityAh ?? 0.0).toStringAsFixed(0)} Ah'))),
            ],
          ),
          const SizedBox(height: JKBMSRTokens.space16),
          _tile(context, TemplateStatusRow(lastSeen: lastSeen, bms: t?.bms ?? BmsExtras.fromJson(null))),
          const SizedBox(height: JKBMSRTokens.space16),
          Text('MORE DETAILS', style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: JKBMSRTokens.space12),
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            // Fixed height instead of a width-derived aspect ratio — see
            // cell_voltage_grid.dart's mainAxisExtent comment for why; the
            // height is scaled with the OS text size so it never clips.
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: JKBMSRTokens.space8,
              mainAxisSpacing: JKBMSRTokens.space8,
              mainAxisExtent: 84 * textScale,
            ),
            children: [
              _smallTile(context, Icons.autorenew, 'Cycle Count', '${bms?.cycleCount ?? 0}'),
              _smallTile(context, Icons.repeat, 'Cycle Capacity', '${(bms?.cycleCapacityAh ?? 0.0).toStringAsFixed(0)} Ah'),
              _smallTile(context, Icons.trending_down, 'Delta Cell V', '${((bms?.deltaCellVoltage ?? 0.0) * 1000).toStringAsFixed(0)} mV'),
              _smallTile(context, Icons.compare_arrows, 'Balance Curr.', '${(bms?.balancingCurrent ?? 0.0).toStringAsFixed(2)} A'),
              _smallTile(context, Icons.thermostat, 'Battery T1', '${(t?.temperature1 ?? 0.0).toStringAsFixed(1)} °C'),
              _smallTile(context, Icons.device_thermostat, 'Battery T2', '${(t?.temperature2 ?? 0.0).toStringAsFixed(1)} °C'),
              _smallTile(context, Icons.memory, 'MOS Temp', '${(bms?.mosfetTemperature ?? 0.0).toStringAsFixed(1)} °C'),
              if (stateOfHealth != null) _smallTile(context, Icons.favorite, 'State of Health', '${stateOfHealth.toStringAsFixed(0)}%'),
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

  Widget _smallTile(BuildContext context, IconData icon, String label, String value) {
    return _tile(
      context,
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: context.colors.accent),
          const SizedBox(height: JKBMSRTokens.space4),
          Text(value, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: JKBMSRTypography.bodySecondary.copyWith(color: context.colors.textPrimary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: JKBMSRTypography.label.copyWith(color: context.colors.textSubtle, fontSize: 11.0)),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(JKBMSRTokens.space12),
      decoration: BoxDecoration(color: context.colors.panel, borderRadius: BorderRadius.circular(JKBMSRTokens.radius8), border: Border.all(color: context.colors.line)),
      child: child,
    );
  }
}
