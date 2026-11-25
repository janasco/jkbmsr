/// Column count for the fixed-column cell matrices (cell voltages and
/// balance-lead resistance).
///
/// The rule is "shed columns as the text grows, never squeeze the text": a
/// tile has to stay at least [minTileWidth] wide *at the current text scale*,
/// because the two monospace lines inside it ("C01" and a voltage) grow with
/// the OS accessibility scale while the phone does not. At 1x on a 360 dp
/// phone the content is 328 dp, so four columns fit; at 2x each tile would be
/// 77 dp wide and the same text cannot fit, so the grid drops to two; at very
/// large scales it drops to one.
///
/// A degenerate width (0, negative, infinite) returns one column rather than
/// zero: a zero-column grid would silently render nothing, which reads as
/// "this pack has no cells".
int gridColumnsFor({
  required double width,
  required double textScale,
  int maxColumns = 4,
  double minTileWidth = 76,
}) {
  if (maxColumns < 1) return 1;
  final scale = (textScale.isFinite && textScale > 0) ? textScale : 1.0;
  if (!width.isFinite || width <= 0) return 1;

  final fit = (width / (minTileWidth * scale)).floor();
  if (fit < 1) return 1;
  if (fit > maxColumns) return maxColumns;
  return fit;
}
