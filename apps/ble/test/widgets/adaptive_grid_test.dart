import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/widgets/adaptive_grid.dart';

// The cell-voltage and wire-resistance matrices are fixed-column grids. At
// 2x text on a 360 dp phone a four-column tile is about 77 px wide, and
// "C01" plus "3.318V" at 22 px cannot fit inside it. The rule these tests
// pin: shed columns as the text grows, never squeeze the text.

void main() {
  group('gridColumnsFor', () {
    test('keeps four columns at 1x on a 328 dp content width', () {
      expect(gridColumnsFor(width: 328, textScale: 1.0), 4);
    });

    test('sheds to two columns at 2x on a 328 dp content width', () {
      expect(gridColumnsFor(width: 328, textScale: 2.0), 2);
    });

    test('sheds to one column at 3x on a 328 dp content width', () {
      expect(gridColumnsFor(width: 328, textScale: 3.0), 1);
    });

    test('a narrow 200 dp width fits two tiles at 1x', () {
      expect(gridColumnsFor(width: 200, textScale: 1.0), 2);
    });

    test('a narrow 200 dp width drops to one tile at 2x', () {
      expect(gridColumnsFor(width: 200, textScale: 2.0), 1);
    });

    test('never exceeds maxColumns however much room there is', () {
      expect(gridColumnsFor(width: 1440, textScale: 1.0), 4);
      expect(
          gridColumnsFor(width: 1440, textScale: 1.0, maxColumns: 6), 6);
    });

    test('never returns less than one column at an extreme scale', () {
      expect(gridColumnsFor(width: 328, textScale: 10.0), 1);
    });

    test('a degenerate zero width still yields one column, not zero', () {
      expect(gridColumnsFor(width: 0, textScale: 1.0), 1);
    });
  });
}
