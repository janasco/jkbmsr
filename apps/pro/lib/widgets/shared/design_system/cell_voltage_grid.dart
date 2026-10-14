import 'package:flutter/material.dart';
import 'colors.dart';
import 'tokens.dart';
import 'typography.dart';
import '../../../models/telemetry.dart';

/// Per-cell voltage view in the web style: a delta pill with a qualitative
/// balance label, a max/min/imbalance summary row, horizontal cell bars in
/// solid blue with orange (min) / green (max) extremes and the voltage
/// printed ON each bar, plus a balance footer. Shared by the main battery
/// dashboard and the standalone Cell Voltages tab.
///
/// The summary value formats ('3.350V', '3.200V', '150mV') and the per-cell
/// format ('3.280 V') are asserted by widget tests — keep them byte-exact.
class JKBMSRCellVoltageGrid extends StatelessWidget {
  final List<CellVoltage> cells;
  final bool isCharging;
  final bool isDischarging;
  final bool animationsEnabled;
  final bool balancing;
  final double balancingCurrent;

  const JKBMSRCellVoltageGrid({
    Key? key,
    required this.cells,
    this.isCharging = false,
    this.isDischarging = false,
    this.animationsEnabled = true,
    this.balancing = false,
    this.balancingCurrent = 0.0,
  }) : super(key: key);

  /// Qualitative balance label mirroring the web CellVoltageTable: "Very
  /// balanced" at or under 10 mV, "Balanced" at or under 30 mV, otherwise
  /// "Check cells".
  static String balanceLabel(int spreadMv) {
    if (spreadMv <= 10) return 'Very balanced';
    if (spreadMv <= 30) return 'Balanced';
    return 'Check cells';
  }

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
    final spreadMv = imbalance.round();
    final label = balanceLabel(spreadMv);
    final calm = cells.length < 2 || spreadMv <= 30;
    final pillColor = calm ? context.colors.accent : context.colors.warning;
    final avgVolt = volts.reduce((a, b) => a + b) / volts.length;

    // Bar scale: relative to this pack's own spread (padded so the extremes
    // never sit exactly on the track edges), so a 5 mV spread still reads as
    // marker spread rather than a flat line.
    final pad = ((maxVolt - minVolt) * 0.15).clamp(0.002, 0.05);
    final lo = minVolt - pad;
    final hi = maxVolt + pad;
    double fraction(double v) => ((v - lo) / (hi - lo)).clamp(0.15, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: title + delta pill.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cell balance · ${cells.length}S',
                    style: JKBMSRTypography.cardHeading,
                  ),
                  Text(
                    'Per-cell voltages · avg ${avgVolt.toStringAsFixed(3)}V',
                    style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: JKBMSRTokens.space8),
            // Flexible (not intrinsic width) so the pill ellipsizes instead
            // of overflowing the header row at large OS text scales.
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: JKBMSRTokens.space8,
                  vertical: JKBMSRTokens.space4,
                ),
                decoration: BoxDecoration(
                  color: pillColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(JKBMSRTokens.radiusFull),
                  border: Border.all(color: pillColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '\u0394 $spreadMv mV · $label',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JKBMSRTypography.label.copyWith(
                    color: pillColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.0,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: JKBMSRTokens.space12),
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
        // Horizontal cell bars: solid blue, orange min, green max, value ON
        // the bar.
        Column(
          children: [
            for (final cell in cells)
              _CellBarRow(
                cellNumber: cell.cell,
                voltage: cell.voltage,
                fraction: fraction(cell.voltage),
                isMin: cells.length > 1 && cell.voltage == minVolt,
                isMax: cells.length > 1 && cell.voltage == maxVolt,
              ),
          ],
        ),
        const SizedBox(height: JKBMSRTokens.space12),
        // Balance status footer.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: JKBMSRTokens.space12,
            vertical: JKBMSRTokens.space8,
          ),
          decoration: BoxDecoration(
            color: context.colors.inset,
            borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Balance',
                style: JKBMSRTypography.bodySecondary.copyWith(color: context.colors.textMuted),
              ),
              Flexible(
                child: Text(
                  balancing
                      ? (balancingCurrent > 0
                          ? 'Balancing · ${balancingCurrent.toStringAsFixed(2)} A'
                          : 'Balancing')
                      : 'Idle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JKBMSRTypography.bodySecondary.copyWith(
                    color: balancing ? context.colors.signal : context.colors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
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

class _CellBarRow extends StatelessWidget {
  final int cellNumber;
  final double voltage;
  final double fraction;
  final bool isMin;
  final bool isMax;

  const _CellBarRow({
    required this.cellNumber,
    required this.voltage,
    required this.fraction,
    required this.isMin,
    required this.isMax,
  });

  @override
  Widget build(BuildContext context) {
    final fillColor = isMax
        ? context.colors.accent
        : isMin
            ? context.colors.warning
            : context.colors.signal;
    final tagColor = isMax
        ? context.colors.accent
        : isMin
            ? context.colors.warning
            : context.colors.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: JKBMSRTokens.space4),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            // scaleDown keeps 'C01'..'C32' inside the fixed slot at large OS
            // text scales; renders naturally at the default scale.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'C${cellNumber.toString().padLeft(2, '0')}',
                maxLines: 1,
                style: JKBMSRTypography.monoTechnical.copyWith(
                  color: tagColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.0,
                ),
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
              child: Container(
                height: 34,
                color: context.colors.control.withValues(alpha: 0.25),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction,
                  child: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: JKBMSRTokens.space8),
                    color: fillColor,
                    // scaleDown keeps the on-bar value inside short fills at
                    // large OS text scales; it renders naturally otherwise.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${voltage.toStringAsFixed(3)} V',
                        maxLines: 1,
                        style: JKBMSRTypography.monoTechnical.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: isMax || isMin
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      isMax ? 'MAX' : 'MIN',
                      textAlign: TextAlign.right,
                      style: JKBMSRTypography.label.copyWith(
                        color: tagColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 10.0,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
