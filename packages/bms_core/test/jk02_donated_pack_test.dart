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


/// Second donated pack: a JK_PB1A16S15P (hw 15A, fw 15.30),
/// contribution `c_01a1c049-bb11-77e7-9f60-668837d9f2f6`, captured 2026-11-09T12:30:19.920950Z.
///
/// A second **different** 8-cell model on the 32-cell layout. The first was a
/// JK_B1A8S10P; this one is a PB-series pack, so the two together pin the sparse
/// 32S case against two real firmwares rather than one. The model name's "16S" is
/// the series count the BMS supports, not the pack: this one has **eight** cells.
const _pbDeviceInfo =
    '55aaeb9003894a4b5f50423141313653313550000000313541000000000031352e3330000000cc5b7d0005000000534f4c41520000000000000000000000313233340000000000000000000000003236303830360000343038303734363139323900303030004a4b2d424d5300000000000000000000323032360000000000000000000000004a4b2d424d5300000000000000000000feffffff8fe91d0200000000901f00000000c0d8e7fe3f00000100000000000000000000ff670000000000000000000000000000ff0f00000000000000000000000000000f00000000000000000000000000000009080001640000005f0000003c000000320000000000000000000000100e00003232011e0000000000000000000000000000000000fe9fe9ff0f0000000000000013';

const _pbCellInfo =
    '55aaeb9002a4e40ce20ce80ce40ce20ce70ce80cde0c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff000000e40c0b0002034300400042004200430041004a0056000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004e010000000020670000eacf040056d1ffff3c013f010000000000000056c832080020950900040000004aa12c0064000000aa5c7d0001010000000000000000000000000000ff00010000008903000021007b5b3f4000000000500a00000001010100060100a54ba000000000004e014301420186034d4ce60cae0000008051010000000200e0d58e049be2590500feff7fdc2f0101b00f000000e6';


/// Third donated PB-series pack, and the first **14-cell** one:
/// JK_PB1A16S10P (hw 15A, fw 15.37),
/// contribution `c_01a1c178-4c09-775d-a43a-5c772482eac7`, captured 2026-11-09T18:00:48.905806Z.
///
/// The corpus had nothing at 14 cells before this: contiguous 8s and packs of 16,
/// 19, 20 and 23. A 14-cell pack on the same 32-slot layout is therefore a third
/// distinct shape for the same offsets.
const _pb14DeviceInfo =
    '55aaeb9003fd4a4b5f50423141313653313050000000313541000000000031352e33370000008849fe02300000004a6b626d730000000000000000000000313233340000000000000000000000003235303430370000343130323334353031343000303030004a4b2d424d5300000000000000000000313233340000000000000000000000004a4b2d424d5300000000000000000000feffffff8fe91d0200000000901f00000000c0d8e7fe3f00000100000000000000000103ff670000000000000000000000000000ff0f000000000000000000000000000001ff670000000000000000000000000009050401640000005f0000003c000000320000000000000000000000100e00003232011e0000000000000000000000000000000000fe9fe9ff0f0000000000000096';

const _pb14CellInfo =
    '55aaeb900218be0dbf0dbf0dbf0dc00dbf0dc10dc10dc10dc00dc00dbf0db80db80d000000000000000000000000000000000000000000000000000000000000000000000000ff3f0000bf0d0800020d5400450049004500490048004a0047004c004a004c004b004d004700000000000000000000000000000000000000000000000000000000000000000000000000ff00000000006dc00000dede020015f1ffffee00ee000000000000000030772c01000071020000000000b5f0010064000000bf49fe0201010000000000000000000000000000ff000100000025040000120099fd3f40000000003e1300000001010100060100fcd46a0100000000ff00f600ec0023046b45e60c58cd00008051010000010203000000000000000000feff7fdc2f0101b00f070000e2';

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
  group('JK02 on a donated JK_PB1A16S15P (15A/15.30)', () {
    test('the device-info frame decodes to the pack it came from', () {
      final info = BmsProtocolHelper.parseJk02DeviceInfoFrame(_bytes(_pbDeviceInfo))!;
      expect(info.modelName, 'JK_PB1A16S15P');
      expect(info.hardwareVersion, '15A');
      expect(info.softwareVersion, '15.30');
    });

    test('the cell-info frame decodes eight cells on the 32S layout', () {
      final status =
          BmsProtocolHelper.parseJk02CellInfoFrame(_bytes(_pbCellInfo), is32s: true)!;

      expect(status.cells, hasLength(8));
      expect(status.enabledCellCount, 8);
      expect(status.totalVoltage, closeTo(26.400000000000002, 0.01));
      expect(status.soc, 86);
      expect(status.mosTemp, closeTo(33.4, 0.5));

      final volts = status.cells.map((c) => c.voltage).toList();
      expect(volts, [
        3.3000000000000003,
        3.298,
        3.3040000000000003,
        3.3000000000000003,
        3.298,
        3.303,
        3.3040000000000003,
        3.294,
      ]);
      // A 24 V nominal pack: eight series cells, not the sixteen the model number
      // allows for.
      expect(volts.fold<double>(0, (a, v) => a + v), closeTo(status.totalVoltage, 0.02));
      for (final v in volts) {
        expect(v, inInclusiveRange(2.0, 3.65));
      }
    });
  });
  group('JK02 on a donated JK_PB1A16S10P (15A/15.37)', () {
    test('the device-info frame decodes to the pack it came from', () {
      final info = BmsProtocolHelper.parseJk02DeviceInfoFrame(_bytes(_pb14DeviceInfo))!;
      expect(info.modelName, 'JK_PB1A16S10P');
      expect(info.hardwareVersion, '15A');
      expect(info.softwareVersion, '15.37');
    });

    test('the cell-info frame decodes fourteen cells on the 32S layout', () {
      final status =
          BmsProtocolHelper.parseJk02CellInfoFrame(_bytes(_pb14CellInfo), is32s: true)!;

      expect(status.cells, hasLength(14));
      expect(status.enabledCellCount, 14);
      expect(status.totalVoltage, closeTo(49.261, 0.01));
      expect(status.soc, 48);
      expect(status.mosTemp, closeTo(25.5, 0.5));

      final volts = status.cells.map((c) => c.voltage).toList();
      expect(volts, [
        3.5180000000000002,
        3.519,
        3.519,
        3.519,
        3.52,
        3.519,
        3.521,
        3.521,
        3.521,
        3.52,
        3.52,
        3.519,
        3.512,
        3.512,
      ]);
      for (final v in volts) {
        expect(v, inInclusiveRange(2.0, 3.65));
      }
    });
  });
}

List<int> _bytes(String hex) => [
      for (var i = 0; i + 1 < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
