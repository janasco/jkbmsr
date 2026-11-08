import 'package:bms_core/bms_core.dart';
import 'package:test/test.dart';

/// The **24S half** of the JK02 cell-info layout.
///
/// `parseJk02CellInfoFrame` has two branches — the 32-cell layout shifts every
/// field after the cell array by 16 bytes — and until now only the 32S branch was
/// covered in this package, by a real donation (`jk02_donated_pack_test.dart`).
/// The 24S branch had no test here at all; the only exercise of it lived in the
/// Contributor app's capture test.
///
/// **This frame is vendor material, not hardware.** It is the JK-B2A24S capture
/// published in `syssi/esphome-jk-bms` (`jk_bms_ble.cpp`), the same one the
/// Contributor's fixtures use. Every contribution received so far comes from a
/// pack whose hardware major is >= 11, which selects the 32S layout, so **no 24S
/// capture from real hardware exists** (see AGENTS.md). A field capture would be a
/// better fixture; this is the best available, and it does pin the offsets.
const _cellInfo24s =
    '55aaeb90028cff0c010d010dff0c010d010dff0c010d010d010d010dff0c010d010d010d010d00000000000000000000'
    '000000000000ffff0000000d000000009d0196018c018701840184018301840185018101830186018201820183018501'
    '0000000000000000000000000000000000000000000003d000000000000000000000be00bf00d2000000000000548e0b'
    '0100683c0100000000003d04000064007904ca0310000101aa06000000000000000000000000070001000000d5020000'
    '0000aed63b400000000058aafdff0000000100020000ece64f0000000000000000000000000000000000000000000000'
    '000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'
    '0000000000000000000000cd';

void main() {
  group('JK02 24S cell-info layout', () {
    test('decodes a contiguous 16-cell pack at the 24S offsets', () {
      final status =
          BmsProtocolHelper.parseJk02CellInfoFrame(_bytes(_cellInfo24s), is32s: false)!;

      expect(status.cells, hasLength(16));
      expect(status.enabledCellCount, 16);
      expect(status.totalVoltage, closeTo(53.251, 0.001));
      expect(status.soc, 84);
      expect(status.cells.first.voltage, closeTo(3.327, 0.001));
      expect(status.cells.last.voltage, closeTo(3.329, 0.001));

      // A contiguous pack: the cells sum to the pack voltage rather than to the
      // average times a layout-dependent count.
      final sum = status.cells.fold<double>(0, (a, c) => a + c.voltage);
      expect(sum, closeTo(status.totalVoltage, 0.02));
      for (final cell in status.cells) {
        expect(cell.voltage, inInclusiveRange(2.0, 3.65));
      }
      expect(status.cells.where((c) => c.wireResistance > 0), hasLength(16));
    });

    test('the layout flag is load-bearing: these bytes read as 32S are wrong', () {
      // The guard that makes layout detection matter. Same bytes, wrong branch:
      // the cell array is misread and the pack voltage no longer appears where
      // the 32S offsets put it.
      final as32s =
          BmsProtocolHelper.parseJk02CellInfoFrame(_bytes(_cellInfo24s), is32s: true)!;

      expect(as32s.cells, hasLength(isNot(16)));
      expect(as32s.totalVoltage, isNot(closeTo(53.251, 0.5)));
    });
  });
}

List<int> _bytes(String hex) => [
      for (var i = 0; i + 1 < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
