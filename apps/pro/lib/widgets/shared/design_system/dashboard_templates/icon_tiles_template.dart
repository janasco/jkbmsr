import 'package:flutter/material.dart';
import 'template_shared.dart';
import '../colors.dart';
import '../tokens.dart';
import '../typography.dart';
import '../cell_voltage_grid.dart';
import '../../../../models/telemetry.dart';
import '../../../../models/telemetry_history_point.dart';

enum _Tone { accent, signal, warning, critical, muted }

/// Dense grid of small icon tiles instead of label/value rows. Only tiles
/// fields this system actually has from the JK-BMS/gateway (no solar, grid,
/// or room-sensor tiles — those don't exist here, so they're not faked).
/// Ported from jkbmsr-web's IconTileTemplate.
class JKBMSRIconTilesTemplate extends StatelessWidget {
  final Telemetry? telemetry;
  final String lastSeen;
  final bool animationsEnabled;
  final List<TelemetryHistoryPoint> history;

  const JKBMSRIconTilesTemplate({
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
    final currentHistory = history.map((point) => point.current).toList();
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('VOLTAGE', maxLines: 1, overflow: TextOverflow.ellipsis, style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted)),
                      Text(
                        '${(t?.voltage ?? 0.0).toStringAsFixed(2)} V',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: JKBMSRTypography.cardHeading.copyWith(color: context.colors.accent),
                      ),
                      const SizedBox(height: JKBMSRTokens.space8),
                      TemplateSparkline(values: voltageHistory, color: context.colors.warning, height: 28),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: JKBMSRTokens.space8),
              Expanded(
                child: _tile(
                  context,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('CURRENT', maxLines: 1, overflow: TextOverflow.ellipsis, style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted)),
                      Text(
                        '${current.toStringAsFixed(2)} A',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: JKBMSRTypography.cardHeading.copyWith(color: context.colors.accent),
                      ),
                      const SizedBox(height: JKBMSRTokens.space8),
                      TemplateSparkline(values: currentHistory, color: context.colors.signal, height: 28),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: JKBMSRTokens.space8),
              Expanded(
                child: _tile(
                  context,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('STATE OF CHARGE', maxLines: 1, overflow: TextOverflow.ellipsis, style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted)),
                      TemplateGauge(
                        percent: soc / 100,
                        valueLabel: '${soc.round()}%',
                        subLabel: '${(bms?.remainingCapacityAh ?? 0.0).toStringAsFixed(1)} Ah remaining',
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
          Text('PACK DETAILS', style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: JKBMSRTokens.space12),
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            // A width-derived childAspectRatio overflowed on narrow phones
            // (icon + 2 lines of text needs a fixed height regardless of
            // how wide 1/3 of the screen ends up being) — mainAxisExtent
            // fixes the height directly instead, scaled with the OS text
            // size so the text never clips at large accessibility scales,
            // same fix as cell_voltage_grid.dart. 102 (not 100) leaves the
            // 1dp of slack a tight icon + two text lines needs at the
            // default scale — 100 clipped by 1dp on the smallest phones.
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: JKBMSRTokens.space8,
              mainAxisSpacing: JKBMSRTokens.space8,
              mainAxisExtent: 102 * textScale,
            ),
            children: [
              _IconTile(icon: Icons.bolt, tone: _Tone.signal, value: '${(t?.power ?? 0.0).toStringAsFixed(0)} W', label: 'Power'),
              _IconTile(icon: Icons.battery_full, tone: _Tone.accent, value: '${(bms?.remainingCapacityAh ?? 0.0).toStringAsFixed(1)} Ah', label: 'Remaining'),
              _IconTile(icon: Icons.inventory_2, tone: _Tone.muted, value: '${(bms?.fullCapacityAh ?? 0.0).toStringAsFixed(0)} Ah', label: 'Total Capacity'),
              _IconTile(icon: Icons.repeat, tone: _Tone.signal, value: '${(bms?.cycleCapacityAh ?? 0.0).toStringAsFixed(0)} Ah', label: 'Cycle Capacity'),
              _IconTile(icon: Icons.autorenew, tone: _Tone.signal, value: '${bms?.cycleCount ?? 0}', label: 'Cycle Count'),
              _IconTile(icon: Icons.power, tone: _Tone.accent, value: '${(bms?.avgCellVoltage ?? 0.0).toStringAsFixed(3)} V', label: 'Avg Cell V'),
              _IconTile(icon: Icons.trending_down, tone: _Tone.warning, value: '${((bms?.deltaCellVoltage ?? 0.0) * 1000).toStringAsFixed(0)} mV', label: 'Delta Cell V'),
              _IconTile(icon: Icons.compare_arrows, tone: _Tone.signal, value: '${(bms?.balancingCurrent ?? 0.0).toStringAsFixed(2)} A', label: 'Balance Curr.'),
              _IconTile(icon: Icons.thermostat, tone: _Tone.warning, value: '${(t?.temperature1 ?? 0.0).toStringAsFixed(1)} °C', label: 'Battery T1'),
              _IconTile(icon: Icons.thermostat, tone: _Tone.warning, value: '${(t?.temperature2 ?? 0.0).toStringAsFixed(1)} °C', label: 'Battery T2'),
              _IconTile(icon: Icons.thermostat, tone: _Tone.critical, value: '${(bms?.mosfetTemperature ?? 0.0).toStringAsFixed(1)} °C', label: 'MOS Temp'),
              if (stateOfHealth != null)
                _IconTile(icon: Icons.favorite, tone: _Tone.accent, value: '${stateOfHealth.toStringAsFixed(0)}%', label: 'State of Health'),
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

  Widget _tile(BuildContext context, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(JKBMSRTokens.space16),
      decoration: BoxDecoration(color: context.colors.panel, borderRadius: BorderRadius.circular(JKBMSRTokens.radius8), border: Border.all(color: context.colors.line)),
      child: child,
    );
  }
}

class _IconTile extends StatelessWidget {
  final IconData icon;
  final _Tone tone;
  final String value;
  final String label;

  const _IconTile({required this.icon, required this.tone, required this.value, required this.label});

  Color _toneColor(BuildContext context) {
    switch (tone) {
      case _Tone.accent:
        return context.colors.accent;
      case _Tone.signal:
        return context.colors.signal;
      case _Tone.warning:
        return context.colors.warning;
      case _Tone.critical:
        return context.colors.critical;
      case _Tone.muted:
        return context.colors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final toneColor = _toneColor(context);
    return Container(
      padding: const EdgeInsets.all(JKBMSRTokens.space8),
      decoration: BoxDecoration(
        color: context.colors.panel,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
        border: Border.all(color: context.colors.line),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: toneColor.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: toneColor),
          ),
          const SizedBox(height: JKBMSRTokens.space8),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: JKBMSRTypography.bodySecondary.copyWith(color: context.colors.textPrimary, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: JKBMSRTokens.space4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: JKBMSRTypography.label.copyWith(color: context.colors.textSubtle, fontSize: 11.0),
          ),
        ],
      ),
    );
  }
}
