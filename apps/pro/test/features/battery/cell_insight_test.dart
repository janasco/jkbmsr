import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/features/battery/cell_insight.dart';

List<CellReading> _cells(List<double> volts) => [
      for (var i = 0; i < volts.length; i++)
        CellReading(cell: i + 1, voltage: volts[i]),
    ];

void main() {
  group('describeCells', () {
    test('a balanced pack names the spread and both extremes', () {
      final insight = describeCells(
        _cells([3.297, 3.292, 3.297, 3.297, 3.305]),
      )!;

      expect(insight.cellCount, 5);
      expect(insight.spreadMv, 13);
      expect(insight.weakestCell, 2);
      expect(insight.strongestCell, 5);
      expect(
        insight.readingsLine,
        'Spread 13 mV · weakest cell #2, strongest #5',
      );
      expect(insight.meaningLine, 'Within the balanced range');
      expect(insight.needsAttention, isFalse);
    });

    test('a very balanced pack says so without changing the numbers', () {
      final insight = describeCells(_cells([3.297, 3.292, 3.295]))!;

      expect(insight.spreadMv, 5);
      expect(insight.meaningLine, 'Well within the balanced range');
      expect(insight.needsAttention, isFalse);
    });

    test('an imbalanced pack names the extremes and asks for a check', () {
      final insight = describeCells(
        _cells([3.300, 3.355, 3.310, 3.300]),
      )!;

      expect(insight.spreadMv, 55);
      expect(insight.weakestCell, 1);
      expect(insight.strongestCell, 2);
      expect(
        insight.readingsLine,
        'Spread 55 mV · weakest cell #1, strongest #2',
      );
      expect(
        insight.meaningLine,
        'Wider than the balanced range — check cells',
      );
      expect(insight.needsAttention, isTrue);
    });

    test('30 mV is inside the balanced range and 31 mV is not', () {
      final atBoundary = describeCells(_cells([3.270, 3.300]))!;
      final pastBoundary = describeCells(_cells([3.269, 3.300]))!;

      expect(atBoundary.spreadMv, 30);
      expect(atBoundary.needsAttention, isFalse);
      expect(pastBoundary.spreadMv, 31);
      expect(pastBoundary.needsAttention, isTrue);
    });

    test('balancing is reported with its current when one was given', () {
      final insight = describeCells(
        _cells([3.297, 3.292, 3.297, 3.297, 3.305]),
        balancing: true,
        balancingCurrentAmps: 0.05,
      )!;

      expect(
        insight.meaningLine,
        'Within the balanced range · balancing at 0.05 A',
      );
    });

    test('balancing without a current is stated without inventing 0 A', () {
      final insight = describeCells(
        _cells([3.297, 3.292, 3.297, 3.297, 3.305]),
        balancing: true,
      )!;

      expect(
        insight.meaningLine,
        'Within the balanced range · balancing now',
      );
    });

    test('a pack that is not balancing makes no balancing claim', () {
      final insight = describeCells(
        _cells([3.297, 3.292]),
        balancing: false,
        balancingCurrentAmps: 5,
      )!;

      expect(insight.meaningLine, isNot(contains('balancing')));
    });

    test('equal cells do not invent a weakest or strongest cell', () {
      final insight = describeCells(_cells([3.300, 3.300, 3.300]))!;

      expect(insight.spreadMv, 0);
      expect(insight.readingsLine, 'Spread 0 mV · no measurable difference');
      expect(insight.meaningLine, 'Well within the balanced range');
    });

    test('an empty reading list has nothing to say', () {
      expect(describeCells(const []), isNull);
    });

    test('one real reading is not enough to compare', () {
      expect(
        describeCells([
          const CellReading(cell: 1, voltage: 3.300),
          const CellReading(cell: 2, voltage: 0),
        ]),
        isNull,
      );
    });

    test('the API zero sentinel is omitted, not read as the weakest cell', () {
      final insight = describeCells(const [
        CellReading(cell: 1, voltage: 0),
        CellReading(cell: 2, voltage: 3.300),
        CellReading(cell: 3, voltage: 3.292),
        CellReading(cell: 4, voltage: 0),
      ])!;

      expect(insight.cellCount, 2);
      expect(insight.spreadMv, 8);
      expect(insight.weakestCell, 3);
      expect(insight.strongestCell, 2);
      expect(
        insight.readingsLine,
        'Spread 8 mV · weakest cell #3, strongest #2',
      );
    });

    test('non-finite and negative voltages are not measurements', () {
      final insight = describeCells(const [
        CellReading(cell: 1, voltage: double.nan),
        CellReading(cell: 2, voltage: 3.300),
        CellReading(cell: 3, voltage: -3.000),
        CellReading(cell: 4, voltage: 3.292),
      ])!;

      expect(insight.cellCount, 2);
      expect(insight.weakestCell, 4);
      expect(insight.strongestCell, 2);
    });

    test('a missing cell number falls back to its position', () {
      final insight = describeCells(const [
        CellReading(cell: 0, voltage: 3.300),
        CellReading(cell: 0, voltage: 3.292),
      ])!;

      expect(insight.weakestCell, 2);
      expect(insight.strongestCell, 1);
    });
  });
}
