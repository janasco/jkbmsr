import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/widgets/adaptive_chip_row.dart';

// The rule behind the three compact status strips: a trailing pill shares the
// line only while the block beside it keeps a readable width. Otherwise the
// pill takes its own line, because squeezing the value or model name to a few
// pixels is how it became an overflow in the first place.

void main() {
  group('chipFitsBeside', () {
    test('shares the line when the pill leaves room for the primary block', () {
      expect(
        chipFitsBeside(
          availableWidth: 280,
          chipWidth: 140,
          leadingWidth: 16,
          minPrimaryWidth: 72,
        ),
        isTrue,
      );
    });

    test('takes its own line when the pill would squeeze the primary block', () {
      expect(
        chipFitsBeside(
          availableWidth: 280,
          chipWidth: 200,
          leadingWidth: 16,
          minPrimaryWidth: 72,
        ),
        isFalse,
      );
    });

    test('the leading block is counted against the available width', () {
      // 238 fits the pill plus the minimum, but only without the 50 dp logo.
      expect(
        chipFitsBeside(
          availableWidth: 238,
          chipWidth: 150,
          leadingWidth: 0,
          minPrimaryWidth: 80,
        ),
        isTrue,
      );
      expect(
        chipFitsBeside(
          availableWidth: 238,
          chipWidth: 150,
          leadingWidth: 50,
          minPrimaryWidth: 80,
        ),
        isFalse,
      );
    });

    test('an unbounded width always shares the line', () {
      expect(
        chipFitsBeside(
          availableWidth: double.infinity,
          chipWidth: 500,
          leadingWidth: 50,
        ),
        isTrue,
      );
    });
  });
}
