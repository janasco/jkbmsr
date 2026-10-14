import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/models/bms_models.dart';

/// `hasCellCountMismatch` is the predicate behind the "Cell Count is Not Equal
/// to Settings" alert. That flag was previously never set by anything, so the
/// alert could not fire; these tests pin the comparison in both directions and,
/// just as importantly, pin the cases that must NOT raise it.
void main() {
  List<CellInfo> cells(int count) => List.generate(
        count,
        (i) => CellInfo(index: i + 1, voltage: 3.3),
      );

  group('hasCellCountMismatch', () {
    test('is false when the reported count equals the configured count', () {
      expect(
        hasCellCountMismatch(configuredCellCount: 16, cells: cells(16)),
        isFalse,
      );
      expect(
        hasCellCountMismatch(configuredCellCount: 32, cells: cells(32)),
        isFalse,
      );
    });

    test('is true when fewer cells report than are configured', () {
      // The real-world case: a sense wire drops, so the pack reports 15 of 16.
      expect(
        hasCellCountMismatch(configuredCellCount: 16, cells: cells(15)),
        isTrue,
      );
    });

    test('is true when more cells report than are configured', () {
      expect(
        hasCellCountMismatch(configuredCellCount: 16, cells: cells(17)),
        isTrue,
      );
    });

    test('is false when the configured count is unknown', () {
      // A telemetry frame that arrives before the settings dump must not
      // invent a mismatch.
      expect(hasCellCountMismatch(configuredCellCount: null, cells: cells(16)), isFalse);
      expect(hasCellCountMismatch(configuredCellCount: 0, cells: cells(16)), isFalse);
      expect(hasCellCountMismatch(configuredCellCount: -4, cells: cells(16)), isFalse);
    });

    test('is false when no cells are reporting', () {
      // The "no cell voltages" state (unpopulated pack, or a transient while
      // balancing) is not a count mismatch.
      expect(hasCellCountMismatch(configuredCellCount: 32, cells: const []), isFalse);
    });

    test('rounds a fractional configured count', () {
      expect(hasCellCountMismatch(configuredCellCount: 16.4, cells: cells(16)), isFalse);
      expect(hasCellCountMismatch(configuredCellCount: 15.6, cells: cells(16)), isFalse);
    });
  });

  group('BmsAlarms.copyWith', () {
    test('sets only the named flag and preserves the rest', () {
      const base = BmsAlarms(cellOverVoltage: true, mosOverTemp: true);
      final next = base.copyWith(cellCountMismatch: true);
      expect(next.cellCountMismatch, isTrue);
      expect(next.cellOverVoltage, isTrue);
      expect(next.mosOverTemp, isTrue);
      expect(next.cellUnderVoltage, isFalse);
      // The original is untouched.
      expect(base.cellCountMismatch, isFalse);
    });

    test('drives the alert text', () {
      expect(
        const BmsAlarms(cellCountMismatch: true).activeAlarmList,
        contains('Cell Count is Not Equal to Settings'),
      );
      expect(const BmsAlarms().hasActiveAlarms, isFalse);
    });
  });
}
