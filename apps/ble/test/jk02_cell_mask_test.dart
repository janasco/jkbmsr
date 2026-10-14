import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/models/bms_models.dart';
import 'package:jkbmsr_ble/protocols/bms_protocol.dart';

/// The JK02 cell-info frame carries two bitmasks this decoder now reads:
/// the "enabled cells" bitmask (the BMS's own cell count, offset 54) and the
/// "wire resistance warning" bitmask (one bit per flagged cell/wire, offset
/// 114). Both are checked against the real JK-B2A24S capture, whose known
/// 16-cell pack makes the expected values unambiguous — syssi's decode
/// documents the encoding the same way (0xFF 0xFF 0x00 0x00 = 16 cells).
const _cellInfo24sHex =
    '55aaeb90028cff0c010d010dff0c010d010dff0c010d010d010d010dff0c010d010d010d010d0000'
    '0000000000000000000000000000ffff0000000d000000009d0196018c0187018401840183018401'
    '850181018301860182018201830185010000000000000000000000000000000000000000000003d0'
    '00000000000000000000be00bf00d2000000000000548e0b0100683c0100000000003d0400006400'
    '7904ca0310000101aa06000000000000000000000000070001000000d50200000000aed63b400000'
    '000058aafdff0000000100020000ece64f0000000000000000000000000000000000000000000000'
    '00000000000000000000000000000000000000000000000000000000000000000000000000000000'
    '00000000000000000000000000000000000000cd';

List<int> _bytes(String hex) => [
      for (var i = 0; i + 1 < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
    ];

/// The JK02 frames use a plain additive 8-bit checksum in the final byte, so an
/// edited frame has to have it recomputed to stay structurally valid.
void _refreshChecksum(List<int> frame) {
  var sum = 0;
  for (var i = 0; i < 299; i++) {
    sum += frame[i];
  }
  frame[299] = sum & 0xFF;
}

void main() {
  test('reads the enabled-cells bitmask and a clean warning bitmask', () {
    final status = BmsProtocolHelper.parseJk02CellInfoFrame(_bytes(_cellInfo24sHex))!;
    expect(status.enabledCellCount, 16); // 0xFFFF in the bitmask
    expect(status.cells.length, 16);
    expect(status.alarms.wireResistanceAnomaly, isFalse);
  });

  test('flags a wire-resistance warning from the frame bitmask', () {
    final frame = _bytes(_cellInfo24sHex);
    frame[114] = 0x04; // the BMS flags cell 3's sense lead
    _refreshChecksum(frame);

    final status = BmsProtocolHelper.parseJk02CellInfoFrame(frame)!;
    expect(status.alarms.wireResistanceAnomaly, isTrue);
    expect(status.alarms.activeAlarmList, contains('Sample-wire Resistance Too Large'));
    expect(status.alarms.hasActiveAlarms, isTrue);
  });

  test('a narrowed enabled-cells bitmask narrows the reported count', () {
    final frame = _bytes(_cellInfo24sHex);
    frame[54] = 0xFF;
    frame[55] = 0x7F; // 0x7FFF -> 15 cells enabled
    frame[36] = 0x00; // ...and cell 16 stops reporting, so both agree at 15
    frame[37] = 0x00;
    _refreshChecksum(frame);

    final status = BmsProtocolHelper.parseJk02CellInfoFrame(frame)!;
    expect(status.enabledCellCount, 15);
    expect(status.cells.length, 15);
    // That is the number the BMS itself reports, and what the mismatch alert
    // compares against the configured count.
    expect(
      hasCellCountMismatch(
        configuredCellCount: 16,
        cells: status.cells,
        enabledCellCount: status.enabledCellCount,
      ),
      isTrue,
    );
    // Consistent inputs must not raise it.
    expect(
      hasCellCountMismatch(
        configuredCellCount: 15,
        cells: status.cells,
        enabledCellCount: status.enabledCellCount,
      ),
      isFalse,
    );
  });
}
