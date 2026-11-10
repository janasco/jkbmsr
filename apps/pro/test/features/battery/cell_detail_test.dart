import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/features/battery/cell_detail.dart';
import 'package:jkbmsr_pro/features/battery/cell_insight.dart';

List<CellReading> _cells(List<double> volts) => [
      for (var i = 0; i < volts.length; i++)
        CellReading(cell: i + 1, voltage: volts[i]),
    ];

// 3.297, 3.292, 3.297, 3.297, 3.305 — the pack the cell grid's own tests use.
// Average 3.2976 V, spread 13 mV, weakest #2, strongest #5.
final _pack = _cells([3.297, 3.292, 3.297, 3.297, 3.305]);

void main() {
  group('describeCell', () {
    test('the weakest cell says so and reads below the pack average', () {
      final detail = describeCell(_pack, index: 1)!;

      expect(detail.title, 'Cell 2');
      expect(detail.voltageValue, '3.292 V');
      expect(detail.averageValue, '3.298 V');
      expect(detail.deviationMv, -6);
      expect(detail.direction, CellDeviationDirection.below);
      expect(detail.deviationValue, '6 mV below average');
      expect(detail.isWeakest, isTrue);
      expect(detail.isStrongest, isFalse);
      expect(detail.roleValue, 'Weakest cell in the pack');
      expect(detail.spreadValue, '13 mV · Balanced');
      expect(detail.spreadMv, 13);
    });

    test('the strongest cell reads above the pack average', () {
      final detail = describeCell(_pack, index: 4)!;

      expect(detail.deviationMv, 7);
      expect(detail.direction, CellDeviationDirection.above);
      expect(detail.deviationValue, '7 mV above average');
      expect(detail.roleValue, 'Strongest cell in the pack');
    });

    test('a middle cell is given no label it has not earned', () {
      final detail = describeCell(_pack, index: 2)!;

      expect(detail.deviationMv, -1);
      expect(detail.deviationValue, '1 mV below average');
      expect(detail.isWeakest, isFalse);
      expect(detail.isStrongest, isFalse);
      expect(detail.roleValue, isNull);
    });

    test('a deviation that rounds to nothing reads as at the average', () {
      final detail = describeCell(_cells([3.300, 3.300]), index: 0)!;

      expect(detail.deviationMv, 0);
      expect(detail.direction, CellDeviationDirection.at);
      expect(detail.deviationValue, 'At the pack average');
      expect(detail.roleValue, isNull);
      expect(detail.spreadValue, '0 mV · Very balanced');
    });

    test('a half-millivolt tie rounds symmetrically in both directions', () {
      final cells = _cells([3.300, 3.290]);

      expect(describeCell(cells, index: 0)!.deviationMv, 5);
      expect(describeCell(cells, index: 1)!.deviationMv, -5);
    });

    test('cells sharing the minimum are not claimed as a single weakest', () {
      final cells = _cells([3.300, 3.290, 3.290]);

      expect(
        describeCell(cells, index: 1)!.roleValue,
        'Shares the lowest voltage in the pack',
      );
      expect(
        describeCell(cells, index: 2)!.roleValue,
        'Shares the lowest voltage in the pack',
      );
      expect(
        describeCell(cells, index: 0)!.roleValue,
        'Strongest cell in the pack',
      );
    });

    test('cells sharing the maximum are not claimed as a single strongest', () {
      final cells = _cells([3.300, 3.300, 3.290]);

      expect(
        describeCell(cells, index: 0)!.roleValue,
        'Shares the highest voltage in the pack',
      );
    });

    test('one cell has nothing to be compared against', () {
      final detail = describeCell(_cells([3.300]), index: 0)!;

      expect(detail.spreadMv, 0);
      expect(detail.deviationMv, 0);
      expect(detail.roleValue, isNull);
    });

    test('the pack spread wears the grid\'s own balance band', () {
      expect(describeCell(_cells([3.290, 3.295]), index: 0)!.spreadValue,
          '5 mV · Very balanced');
      expect(describeCell(_cells([3.270, 3.300]), index: 0)!.spreadValue,
          '30 mV · Balanced');
      expect(describeCell(_cells([3.269, 3.300]), index: 0)!.spreadValue,
          '31 mV · Check cells');
    });

    test('balancing reports its current, and only then', () {
      expect(
        describeCell(_pack, index: 0, balancing: true, balancingCurrentAmps: 0.05)!
            .balancingValue,
        '0.05 A',
      );
      expect(
        describeCell(_pack, index: 0, balancing: true)!.balancingValue,
        'Active',
      );
      expect(
        describeCell(_pack, index: 0)!.balancingValue,
        'Idle',
      );
    });

    group('readings the payload did not take', () {
      test('an omitted cell opens no sheet', () {
        final cells = [
          const CellReading(cell: 1, voltage: 0),
          const CellReading(cell: 2, voltage: 3.296),
          const CellReading(cell: 3, voltage: 3.300),
        ];

        expect(describeCell(cells, index: 0), isNull);
      });

      test('non-finite and negative voltages open no sheet', () {
        expect(
          describeCell(
            const [CellReading(cell: 1, voltage: double.nan)],
            index: 0,
          ),
          isNull,
        );
        expect(
          describeCell(
            const [CellReading(cell: 1, voltage: -3.3)],
            index: 0,
          ),
          isNull,
        );
      });

      test('an omitted cell does not move the average for the rest', () {
        final cells = [
          const CellReading(cell: 1, voltage: 0),
          const CellReading(cell: 2, voltage: 3.296),
          const CellReading(cell: 3, voltage: 3.300),
        ];

        final detail = describeCell(cells, index: 2)!;

        expect(detail.averageValue, '3.298 V');
        expect(detail.deviationValue, '2 mV above average');
        expect(detail.roleValue, 'Strongest cell in the pack');
        expect(detail.spreadValue, '4 mV · Very balanced');
      });

      test('a row outside the list opens no sheet', () {
        expect(describeCell(_pack, index: -1), isNull);
        expect(describeCell(_pack, index: _pack.length), isNull);
        expect(describeCell(const [], index: 0), isNull);
      });
    });
  });
}
