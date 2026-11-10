import '../../widgets/shared/design_system/cell_voltage_grid.dart';
import 'cell_insight.dart';

/// Which side of the pack average a cell sits on, after rounding.
enum CellDeviationDirection { below, at, above }

/// One cell described against the rest of its pack.
///
/// Every value is derived from the readings passed to [describeCell]. Nothing
/// is inferred from a field the payload did not carry, and the wording never
/// claims a comparison the readings cannot support.
class CellDetail {
  const CellDetail({
    required this.cell,
    required this.voltage,
    required this.averageVoltage,
    required this.deviationMv,
    required this.isWeakest,
    required this.isStrongest,
    required this.lowestTieCount,
    required this.highestTieCount,
    required this.spreadMv,
    required this.balancing,
    required this.balancingCurrentAmps,
  });

  final int cell;
  final double voltage;

  /// Mean voltage of the cells that reported a real reading. Omitted cells
  /// (which the API serialises as 0) are excluded, so one absent reading does
  /// not move the average every other cell is compared against.
  final double averageVoltage;

  /// Signed deviation from [averageVoltage] in millivolts, rounded the same
  /// way the grid rounds its own imbalance figure.
  final int deviationMv;

  /// First cell at the pack minimum, meaningful only when the pack actually
  /// has a spread.
  final bool isWeakest;

  /// First cell at the pack maximum, meaningful only when the pack actually
  /// has a spread.
  final bool isStrongest;

  /// How many cells carry the pack minimum. More than one means the cell
  /// shares the lowest voltage rather than holding that position alone.
  final int lowestTieCount;

  /// How many cells carry the pack maximum.
  final int highestTieCount;

  /// Strongest minus weakest, in millivolts, rounded like the cell grid.
  final int spreadMv;

  final bool balancing;
  final double balancingCurrentAmps;

  String get title => 'Cell $cell';

  /// The cell's own voltage, at the three decimals the grid prints.
  String get voltageValue => '${voltage.toStringAsFixed(3)} V';

  /// The pack average the deviation is measured against.
  String get averageValue => '${averageVoltage.toStringAsFixed(3)} V';

  CellDeviationDirection get direction => switch (deviationMv) {
        < 0 => CellDeviationDirection.below,
        > 0 => CellDeviationDirection.above,
        _ => CellDeviationDirection.at,
      };

  String get deviationValue => switch (direction) {
        CellDeviationDirection.below => '${-deviationMv} mV below average',
        CellDeviationDirection.above => '$deviationMv mV above average',
        CellDeviationDirection.at => 'At the pack average',
      };

  /// The cell's position in the pack, or null when it is neither extreme —
  /// a middle cell is not given a label it has not earned.
  String? get roleValue {
    if (isWeakest) {
      return lowestTieCount > 1
          ? 'Shares the lowest voltage in the pack'
          : 'Weakest cell in the pack';
    }
    if (isStrongest) {
      return highestTieCount > 1
          ? 'Shares the highest voltage in the pack'
          : 'Strongest cell in the pack';
    }
    return null;
  }

  /// The pack's spread, labelled with the grid's own balance band so the sheet
  /// and the bars cannot disagree about the same pack.
  String get spreadValue =>
      '$spreadMv mV · ${JKBMSRCellVoltageGrid.balanceLabel(spreadMv)}';

  /// Balancing state at the const current, when one was reported. "Idle" is
  /// the grid's own wording for the same flag.
  String get balancingValue {
    if (!balancing) return 'Idle';
    if (balancingCurrentAmps > 0) {
      return '${balancingCurrentAmps.toStringAsFixed(2)} A';
    }
    return 'Active';
  }
}

/// Describes the cell at [index] within [cells], or returns null when that row
/// has no measurement to describe.
///
/// [index] is the position of the tapped row in the same list the grid renders,
/// so an omitted reading (the API's 0 sentinel, a non-finite value) opens no
/// sheet rather than inventing a voltage for it.
CellDetail? describeCell(
  List<CellReading> cells, {
  required int index,
  bool balancing = false,
  double balancingCurrentAmps = 0,
}) {
  if (index < 0 || index >= cells.length) return null;
  final tapped = cells[index];
  if (!tapped.voltage.isFinite || tapped.voltage <= 0) return null;

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

  var sum = 0.0;
  var lowest = present.first.voltage;
  var highest = present.first.voltage;
  for (final cell in present) {
    sum += cell.voltage;
    if (cell.voltage < lowest) lowest = cell.voltage;
    if (cell.voltage > highest) highest = cell.voltage;
  }

  var lowestTieCount = 0;
  var highestTieCount = 0;
  for (final cell in present) {
    if (cell.voltage == lowest) lowestTieCount++;
    if (cell.voltage == highest) highestTieCount++;
  }

  final average = sum / present.length;
  final hasSpread = highest > lowest;

  return CellDetail(
    cell: tapped.cell > 0 ? tapped.cell : index + 1,
    voltage: tapped.voltage,
    averageVoltage: average,
    deviationMv: ((tapped.voltage - average) * 1000).round(),
    isWeakest: hasSpread && tapped.voltage == lowest,
    isStrongest: hasSpread && tapped.voltage == highest,
    lowestTieCount: lowestTieCount,
    highestTieCount: highestTieCount,
    spreadMv: ((highest - lowest) * 1000).round(),
    balancing: balancing,
    balancingCurrentAmps: balancingCurrentAmps,
  );
}
