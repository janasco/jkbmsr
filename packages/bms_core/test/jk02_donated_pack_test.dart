import 'package:bms_core/bms_core.dart';
import 'package:test/test.dart';

/// A real donation, decoded.
///
/// Provenance: contribution `c_01a1ba58-baa8-7887-b6fa-362a2d5b3f31`, captured
/// 2026-11-08T08:48:59.560305Z from a JK_B1A8S10P (hardware 11A,
/// firmware 11.55).
///
/// It is here because it is the only byte-for-byte case in this suite of the
/// **32-cell register layout with a sparse cell array**: eight cells on a layout
/// that addresses 32. Every other fixture is a contiguous 16-cell 24S pack from
/// vendor material, so nothing exercised the 32S offsets with a partially
/// populated frame. The pack also carries wire-resistance data, which the 24S
/// fixtures do not.
///
/// The frames are copied verbatim from the donation. The expected values are what
/// that donation's own payload reported for the same frame, so this is a
/// regression pin rather than an independent truth: if the parser changes, this
/// fails and someone has to say which side is right. `tool/verify_contribution.dart`
/// performs the same comparison against a whole payload.
const _deviceInfo = '55aaeb9003e94a4b5f42314138533130500000000000313141000000000031312e353500000064715403150000003431313031343330303630000000000030323037303830390000000000000000323530313330000034313130313433303036300030303000496e70757420557365726461746100003132333435000000000000000000000000000000000000000000000000000000fef9ffff9f2d000200000000901f00000000c0d8e732000000010000000000000000000007240000000000000000000000000000410000000000000000000000000000000000000000000000000000000000000009000000640000005f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000febf210600000000000000006d';

const _cellInfo = '55aaeb900204f40ce90cf40cf40cf20cf50cf40cf30c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff000000f20c030005013200330033003200330033003200320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076010000000094670000eac1030021e0ffff37014501000000000000005252810300c045040002000000469b080064000000af71540301010000000000000000000000000000ff0001000000640306005e00ec244040000000005b0a00000001000100060000e70aba01000000007601000000006003e5c6e40c99e600008051010000000000000000000000000001feff7fdc2f01018103000000eb';

void main() {
  group('JK02 on a donated JK_B1A8S10P (11A/11.55)', () {
    test('the device-info frame decodes to the pack it came from', () {
      final info = BmsProtocolHelper.parseJk02DeviceInfoFrame(_bytes(_deviceInfo))!;
      expect(info.modelName, 'JK_B1A8S10P');
      expect(info.hardwareVersion, '11A');
      expect(info.softwareVersion, '11.55');
    });

    test('the cell-info frame decodes eight cells on the 32S layout', () {
      final status =
          BmsProtocolHelper.parseJk02CellInfoFrame(_bytes(_cellInfo), is32s: true)!;

      // A sparse pack: the layout addresses 32 slots and eight reported a
      // voltage. A dense array would put 0.0 V in the empty slots instead.
      expect(status.cells, hasLength(8));
      expect(status.enabledCellCount, 8);

      expect(status.totalVoltage, closeTo(26.516000000000002, 0.01));
      expect(status.currentA, closeTo(-8.159, 0.05));
      expect(status.soc, 82);
      expect(status.mosTemp, closeTo(37.4, 0.5));

      final volts = status.cells.map((c) => c.voltage).toList();
      expect(volts, [
        3.3160000000000003,
        3.305,
        3.3160000000000003,
        3.3160000000000003,
        3.314,
        3.317,
        3.3160000000000003,
        3.315,
      ]);
      for (final v in volts) {
        expect(v, inInclusiveRange(2.0, 3.65), reason: 'a cell voltage');
      }
    });

    test('the frame carries wire resistance for the cells it reported', () {
      final status =
          BmsProtocolHelper.parseJk02CellInfoFrame(_bytes(_cellInfo), is32s: true)!;
      expect(status.cells.where((c) => c.wireResistance > 0), isNotEmpty);
    });
  });
}

List<int> _bytes(String hex) => [
      for (var i = 0; i + 1 < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
