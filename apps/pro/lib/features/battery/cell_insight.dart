import '../../widgets/shared/design_system/cell_voltage_grid.dart';

/// One cell reading as the explainer needs it: an identifier and a voltage.
///
/// This is deliberately a plain value rather than a model or widget type so the
/// wording can be exercised without building a screen.
class CellReading {
  const CellReading({required this.cell, required this.voltage});

  final int cell;
  final double voltage;
}

/// The cell grid's qualitative balance band, named without its display text.
enum CellSpreadBand { veryBalanced, balanced, checkCells }

/// A plain-language reading of the cell voltages currently on screen.
///
/// Every statement is derived from the readings passed in. Values the payload
/// did not report are never represented by a placeholder; when there is not
/// enough to compare, [describeCells] returns null and the caller renders
/// nothing.
class CellInsight {
  const CellInsight({
    required this.cellCount,
    required this.spreadMv,
    required this.weakestCell,
    required this.strongestCell,
    required this.band,
    required this.balancing,
    required this.balancingCurrentAmps,
  });

  /// Number of readings that carried a real voltage. Omitted cells (which the
  /// API serialises as 0) are excluded before this is counted.
  final int cellCount;

  /// Strongest minus weakest, in millivolts, rounded exactly as the cell grid
  /// rounds its own imbalance figure.
  final int spreadMv;

  /// First cell at the minimum voltage. Meaningful only when [spreadMv] > 0.
  final int weakestCell;

  /// First cell at the maximum voltage. Meaningful only when [spreadMv] > 0.
  final int strongestCell;

  final CellSpreadBand band;

  /// True only when the BMS reported balancing. An absent flag is not read as
  /// "idle", so the explainer makes no claim in that case.
  final bool balancing;

  /// The balancing current in amps, or a non-positive value when it was not
  /// reported.
  final double balancingCurrentAmps;

  /// The spread and the cells at each end.
  String get readingsLine => spreadMv == 0
      ? 'Spread 0 mV · no measurable difference'
      : 'Spread $spreadMv mV · weakest cell #$weakestCell, '
          'strongest #$strongestCell';

  /// What that spread means, plus balancing when the BMS reported it.
  String get meaningLine {
    final verdict = switch (band) {
      CellSpreadBand.veryBalanced => 'Well within the balanced range',
      CellSpreadBand.balanced => 'Within the balanced range',
      CellSpreadBand.checkCells =>
        'Wider than the balanced range, check cells',
    };
    if (!balancing) return verdict;
    if (balancingCurrentAmps > 0) {
      return '$verdict · balancing at '
          '${balancingCurrentAmps.toStringAsFixed(2)} A';
    }
    return '$verdict · balancing now';
  }

  /// True when the spread is past the app's balanced boundary and the cell
  /// view would label the pack "Check cells".
  bool get needsAttention => band == CellSpreadBand.checkCells;
}

/// Describes [cells], or returns null when fewer than two cells reported a
/// comparison-able voltage.
///
/// A non-positive or non-finite voltage is treated as an omitted reading, not
/// as a real measurement: the API fills absent fields with 0, and a cell view
/// that treated that as the weakest cell would attribute an imbalance to a
/// reading nobody took.
CellInsight? describeCells(
  List<CellReading> cells, {
  bool balancing = false,
  double balancingCurrentAmps = 0,
}) {
  final present = <CellReading>[];
  for (var i = 0; i < cells.length; i++) {
    final cell = cells[i];
    if (!cell.voltage.isFinite || cell.voltage <= 0) continue;
    present.add(
      CellReading(
        cell: cell.cell > 0 ? cell.cell : i + 1,
        voltage: cell.voltage,
      ),
    );
  }
  if (present.length < 2) return null;

  var weakest = present.first;
  var strongest = present.first;
  for (final cell in present.skip(1)) {
    if (cell.voltage < weakest.voltage) weakest = cell;
    if (cell.voltage > strongest.voltage) strongest = cell;
  }

  final spreadMv = ((strongest.voltage - weakest.voltage) * 1000).round();
  return CellInsight(
    cellCount: present.length,
    spreadMv: spreadMv,
    weakestCell: weakest.cell,
    strongestCell: strongest.cell,
    band: _bandFor(spreadMv),
    balancing: balancing,
    balancingCurrentAmps: balancingCurrentAmps,
  );
}

/// Reads the band from the cell grid's own public balance label, so the
/// explainer and the grid cannot disagree about the same pack. The grid is the
/// definition of the boundary; this function only maps its wording to an enum.
CellSpreadBand _bandFor(int spreadMv) {
  switch (JKBMSRCellVoltageGrid.balanceLabel(spreadMv)) {
    case 'Very balanced':
      return CellSpreadBand.veryBalanced;
    case 'Balanced':
      return CellSpreadBand.balanced;
    default:
      // Any future label that is not one of the calm bands is treated as
      // needing attention rather than silently reading as balanced.
      return CellSpreadBand.checkCells;
  }
}
