import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/protocols/bms_protocol.dart';

/// Real captured JK02 frames, embedded as hex so a transcription error is
/// caught rather than silently passing. Provenance for each:
///
///  * `_devInfo24sHex` / `_devInfo32sHex` — the two real device-info captures
///    printed in syssi/esphome-jk-bms `jk_bms_ble.cpp`'s `decode_device_info_`
///    comment block (a JK02_24S and a JK02_32S pack). These are the frames
///    whose byte offsets the decoder asserts.
///  * `_logbookHex` — the captured logbook frame at
///    syssi/esphome-jk-bms `tests/components/jk_bms_ble/frames_logbook.h`
///    ("Captured logbook frame (command 0xA1 → frame type 0x05)").
///
/// Every frame carries its captured CRC in the trailing byte, and the parser
/// validates that CRC — so these tests exercise the real wire format, not a
/// hand-built shape.
const _devInfo24sHex =
    '55aaeb90039f4a4b2d4232413234533135500000000031302e585700000031302e303700000040af0100060000'
    '004a4b2d4232413234533135500000000031323334000000000000000000000000323230343037000032303231'
    '363032303936003030303000496e70757420557365726461746100003132333435360000000000000000000000'
    '000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'
    '000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'
    '000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'
    '000000000000000000000000000000000000000000000000000000000065';

const _devInfo32sHex =
    '55aaeb9003c94a4b5f5042324131365331355000000031342e584100000031342e323000000054e601009c0000'
    '004a4b5f5042324131365331355000000031323334000000000000000000000000323331313138000033303932'
    '353732313334003030303000496e70757420557365726461746100003132333435370000000000000000000049'
    '6e7075742055736572646174610000feffffffafe9010200000000901f00000000c0d8e7fe1f00000100000000'
    '000000000104cf030000000000000000000000000000df07000000000000000000000000000001cf0300000000'
    '000000000000000000000b00010000000000000000090000000b0000000000000000000000805100000a500100'
    '0000000000000000000000000000000000fe9fe9fe03000000000000001b';

const _logbookHex =
    '55aaeb90051f04000000030000000001ee00000044af5c26001bd85c26001c0000000000000000000000000000'
    '000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'
    '000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'
    '000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'
    '000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'
    '000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'
    '00000000000000000000000000000000000000000000000000000000009a';

List<int> _hex(String s) {
  final out = <int>[];
  for (int i = 0; i + 1 < s.length; i += 2) {
    out.add(int.parse(s.substring(i, i + 2), radix: 16));
  }
  return out;
}

/// Recomputes the trailing CRC after a test mutates a frame, so the test can
/// isolate "wrong frame type" from "bad checksum".
void _reCrc(List<int> f) {
  int sum = 0;
  for (int i = 0; i < f.length - 1; i++) {
    sum += f[i];
  }
  f[f.length - 1] = sum & 0xFF;
}

void main() {
  group('JK02 device info (frame type 0x03)', () {
    test('24S captured frame decodes identity fields at syssi offsets', () {
      final f = _hex(_devInfo24sHex);
      expect(f.length, 300);

      final info = BmsProtocolHelper.parseJk02DeviceInfoFrame(f);
      expect(info, isNotNull);
      expect(info!.modelName, 'JK-B2A24S15P');
      expect(info.hardwareVersion, '10.XW');
      expect(info.softwareVersion, '10.07');
      expect(info.uptimeSeconds, 110400);
      expect(info.powerOnCount, 6);
      expect(info.serialNumber, '2021602096');
      expect(info.manufacturingDate, '2022-04-07');
      expect(BmsProtocolHelper.parseJk02DeviceInfoIs32s(f), isFalse);
    });

    test('32S captured frame decodes and is detected as 32-cell', () {
      final f = _hex(_devInfo32sHex);
      final info = BmsProtocolHelper.parseJk02DeviceInfoFrame(f);
      expect(info, isNotNull);
      expect(info!.modelName, 'JK_PB2A16S15P');
      expect(info.hardwareVersion, '14.XA');
      expect(info.softwareVersion, '14.20');
      expect(info.uptimeSeconds, 124500);
      expect(info.powerOnCount, 156);
      expect(info.serialNumber, '3092572134');
      expect(info.manufacturingDate, '2023-11-18');
      expect(BmsProtocolHelper.parseJk02DeviceInfoIs32s(f), isTrue);
    });

    test('a corrupted CRC is rejected, never misread as data', () {
      final f = _hex(_devInfo24sHex);
      f[299] ^= 0xFF;
      expect(BmsProtocolHelper.parseJk02DeviceInfoFrame(f), isNull);
    });

    test('a settings frame (type 0x01) is not accepted as device info', () {
      final f = _hex(_devInfo24sHex);
      f[4] = 0x01;
      _reCrc(f);
      expect(BmsProtocolHelper.parseJk02DeviceInfoFrame(f), isNull);
    });
  });

  group('JK02 logbook (frame type 0x05)', () {
    test('retrieve command is the verified 0xA1 frame with correct CRC', () {
      final cmd = BmsProtocolHelper.buildJk02LogbookRequest();
      expect(cmd.length, 20);
      expect(cmd.sublist(0, 5), [0xAA, 0x55, 0x90, 0xEB, 0xA1]);
      expect(cmd[19], 0x1B); // sum(bytes[0..18]) & 0xFF
      expect(BmsProtocolHelper.jk02CommandLogbook, 0xA1);
    });

    test('captured logbook frame decodes count and every entry', () {
      final f = _hex(_logbookHex);
      expect(f.length, 300);

      final lb = BmsProtocolHelper.parseJk02LogbookFrame(f);
      expect(lb, isNotNull);
      expect(lb!.logCount, 4);
      expect(lb.entries.length, 4);

      expect(lb.entries[0].code, 0x01);
      expect(lb.entries[0].name, 'Boot');
      expect(lb.entries[0].seconds, 0);

      expect(lb.entries[1].code, 0x44);
      expect(lb.entries[1].name, 'Factory setting LFP');
      expect(lb.entries[1].seconds, 238);

      expect(lb.entries[2].code, 0x1B);
      expect(lb.entries[2].name, 'Charge low temperature protection');
      expect(lb.entries[2].seconds, 2514095);

      expect(lb.entries[3].code, 0x1C);
      expect(lb.entries[3].name, 'Charge low temperature protection is released');
      expect(lb.entries[3].seconds, 2514136);
    });

    test('a corrupted CRC is rejected', () {
      final f = _hex(_logbookHex);
      f[299] ^= 0xFF;
      expect(BmsProtocolHelper.parseJk02LogbookFrame(f), isNull);
    });

    test('a device-info frame is not accepted as a logbook', () {
      final f = _hex(_devInfo24sHex);
      expect(BmsProtocolHelper.parseJk02LogbookFrame(f), isNull);
    });

    test('event codes map to syssi names across the documented ranges', () {
      expect(BmsProtocolHelper.jk02LogbookCodeName(0x00), '');
      expect(BmsProtocolHelper.jk02LogbookCodeName(0x01), 'Boot');
      expect(BmsProtocolHelper.jk02LogbookCodeName(0x49), 'Discharge under temperature protection Release');
      expect(BmsProtocolHelper.jk02LogbookCodeName(0x64), 'Cell 01 over charge protection');
      expect(BmsProtocolHelper.jk02LogbookCodeName(0x83), 'Cell 32 over charge protection');
      expect(BmsProtocolHelper.jk02LogbookCodeName(0xC8), 'Cell 01 over discharge protection');
      expect(BmsProtocolHelper.jk02LogbookCodeName(0xE7), 'Cell 32 over discharge protection');
      expect(BmsProtocolHelper.jk02LogbookCodeName(0xFF), '');
    });

    test('the entry count is capped at 50 even if the BMS reports more', () {
      final f = List<int>.filled(300, 0);
      f[0] = 0x55;
      f[1] = 0xAA;
      f[2] = 0xEB;
      f[3] = 0x90;
      f[4] = 0x05;
      f[6] = 200; // log_count = 200
      _reCrc(f);
      final lb = BmsProtocolHelper.parseJk02LogbookFrame(f);
      expect(lb, isNotNull);
      expect(lb!.logCount, 200);
      expect(lb.entries.length, 50);
    });
  });
}
