import 'package:flutter/material.dart';
import 'colors.dart';
import 'tokens.dart';
import 'typography.dart';
import 'battery_indicator.dart';
import '../../../models/telemetry.dart';

/// Per-cell voltage grid with a max/min/imbalance summary row. Shared by the
/// main battery dashboard (embedded, so individual cell voltages are visible
/// without leaving the gateway's device screen) and the standalone Cell
/// Voltages tab (full-page, with its own polling/loading/error states).
class JKBMSRCellVoltageGrid extends StatelessWidget {
  final List<CellVoltage> cells;
  final bool isCharging;
  final bool isDischarging;
  final bool animationsEnabled;

  const JKBMSRCellVoltageGrid({
    Key? key,
    required this.cells,
    this.isCharging = false,
    this.isDischarging = false,
    this.animationsEnabled = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(JKBMSRTokens.space16),
        decoration: BoxDecoration(
          color: context.colors.inset,
          borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
        ),
        child: Text(
          'No cell telemetry data yet.',
          style: JKBMSRTypography.bodySecondary.copyWith(color: context.colors.textMuted),
        ),
      );
    }

    final volts = cells.map((c) => c.voltage).toList();
    final maxVolt = volts.reduce((a, b) => a > b ? a : b);
    final minVolt = volts.reduce((a, b) => a < b ? a : b);
    final imbalance = (maxVolt - minVolt) * 1000;

    // Grow the fixed tile height with the OS text scale so the voltage line
    // plus the battery indicator never clip at large accessibility sizes.
    // At the default scale this is exactly 1.0 (a no-op).
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(JKBMSRTokens.space12),
          decoration: BoxDecoration(
            color: context.colors.inset,
            borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
          ),
          child: Row(
            children: [
              Expanded(child: _buildStat(context, 'Max Cell', '${maxVolt.toStringAsFixed(3)}V')),
              _buildDivider(context),
              Expanded(child: _buildStat(context, 'Min Cell', '${minVolt.toStringAsFixed(3)}V')),
              _buildDivider(context),
              Expanded(child: _buildStat(context, 'Imbalance', '${imbalance.toStringAsFixed(0)}mV')),
            ],
          ),
        ),
        const SizedBox(height: JKBMSRTokens.space12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: JKBMSRTokens.space12,
            mainAxisSpacing: JKBMSRTokens.space12,
            // A fixed childAspectRatio ties this cell's height to its
            // (screen-width-dependent) column width, which is exactly
            // backwards — the content (card padding + one line of text +
            // the battery indicator) needs a fixed height regardless of how
            // wide the column ends up. A ratio tuned to look right on one
            // screen width overflowed on narrower ones; mainAxisExtent
            // fixes the height directly instead, scaled with the OS text
            // size so the text never clips at large accessibility scales.
            mainAxisExtent: 64 * textScale,
          ),
          itemCount: cells.length,
          itemBuilder: (context, index) {
            final cell = cells[index];
            final volt = cell.voltage;
            // Percent within range 2.5V (empty) to 3.65V (full).
            final percent = ((volt - 2.5) / (3.65 - 2.5)).clamp(0.0, 1.0);

            return Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: JKBMSRTokens.space12, vertical: JKBMSRTokens.space8),
                child: Row(
                  children: [
                    Container(
                      alignment: Alignment.center,
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: context.colors.line,
                        shape: BoxShape.circle,
                      ),
                      // scaleDown keeps the one- or two-digit cell number
                      // inside the 28dp circle at large text scales; it
                      // renders at its natural size at the default scale.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${cell.cell}',
                          style: JKBMSRTypography.monoTechnical.copyWith(
                            fontSize: 12.0,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: JKBMSRTokens.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${volt.toStringAsFixed(3)} V',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: JKBMSRTypography.monoTechnical.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: JKBMSRTokens.space4),
                          JKBMSRBatteryIndicator(
                            percent: percent,
                            width: 56,
                            height: 20,
                            isCharging: isCharging,
                            isDischarging: isDischarging,
                            cellIndex: cell.cell,
                            animationsEnabled: animationsEnabled,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildStat(BuildContext context, String label, String val) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: JKBMSRTypography.label),
        const SizedBox(height: JKBMSRTokens.space4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(val, maxLines: 1, style: JKBMSRTypography.monoTechnical.copyWith(fontSize: 16.0, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color: context.colors.line,
    );
  }
}
