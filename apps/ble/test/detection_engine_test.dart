import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/models/bms_models.dart';
import 'package:jkbmsr_ble/models/bms_parameter.dart';
import 'package:jkbmsr_ble/protocols/bms_protocol.dart';
import 'package:jkbmsr_ble/services/detection_engine.dart';

const kDalyService = '0000fff0-0000-1000-8000-00805f9b34fb';
const kBasenService = '0000fa00-0000-1000-8000-00805f9b34fb';
const kShared00 = '0000ff00-0000-1000-8000-00805f9b34fb';
const kSharedE0 = '0000ffe0-0000-1000-8000-00805f9b34fb';

void main() {
  group('DetectionEngine', () {
    test('name match is authoritative and needs no probe', () {
      final candidates = DetectionEngine.candidatesFor(
        name: 'JK-BD6A20S10P',
        serviceUuids: {kShared00, kSharedE0},
      );
      expect(candidates, isNotEmpty);
      expect(candidates.first.brand, BmsBrand.jkbms);
      expect(candidates.first.confidence, 1.0);
      expect(candidates.first.requiresProbe, isFalse);
    });

    test('specialized prefix resolves before broad name contains', () {
      final candidates = DetectionEngine.candidatesFor(
        name: 'ANT24S',
        serviceUuids: {kShared00},
      );
      expect(candidates.first.brand, BmsBrand.ant);
      // A name match is treated as authoritative — no probe needed.
      expect(candidates.first.confidence, 1.0);
      expect(candidates.first.requiresProbe, isFalse);
    });

    test('exclusive service UUID scores 0.6 and needs a probe', () {
      final candidates = DetectionEngine.candidatesFor(
        name: 'BMS 2023 MODULE',
        serviceUuids: {kBasenService},
      );
      expect(candidates.first.brand, BmsBrand.basen);
      expect(candidates.first.confidence, 0.6);
      expect(candidates.first.requiresProbe, isTrue);
    });

    test('shared 0xFF00 service produces multiple weak candidates', () {
      final candidates = DetectionEngine.candidatesFor(
        name: '',
        serviceUuids: {kShared00},
      );
      expect(candidates, isNotEmpty);
      expect(candidates.first.confidence, 0.4);
      // 0xFF00 is used by JK-JK02 alias, JBD, Seplos, Tianpower and KS.
      expect(candidates.length, greaterThanOrEqualTo(3));
    });

    test('shared service 0xFFF0 yields Daly first (tied 0.4 with OGT)', () {
      final candidates = DetectionEngine.candidatesFor(
        name: 'BMS 2023 MODULE',
        serviceUuids: {kDalyService},
      );
      expect(candidates.first.brand, BmsBrand.daly);
      expect(candidates.first.confidence, 0.4);
      expect(candidates.first.requiresProbe, isTrue);
      expect(candidates.map((c) => c.brand), contains(BmsBrand.ogt));
    });

    test('unknown input yields no candidates', () {
      final candidates = DetectionEngine.candidatesFor(
        name: 'ESP32-BLE-1234',
        serviceUuids: {'0000180a-0000-1000-8000-00805f9b34fb'},
      );
      expect(candidates, isEmpty);
    });
  });

  group('settings protocol', () {
    test('JK02 settings frame decode boundary', () {
      final frame = List<int>.filled(300, 0);
      frame[0] = 0x55;
      frame[1] = 0xAA;
      frame[2] = 0xEB;
      frame[3] = 0x90;
      frame[4] = 0x01;
      _writeU32(frame, 10, 2600); // Cell Undervoltage Protection: 2.60 V
      frame[114] = 16; // Cell count
      // Checksum (byte 299) = low byte of the sum of bytes 0..298.
      int sum = 0;
      for (int i = 0; i < 299; i++) {
        sum += frame[i];
      }
      frame[299] = sum & 0xFF;
      final raw = BmsProtocolHelper.parseJk02SettingsFrame(frame);
      expect(raw, isNotNull);
      final cellUvp = raw![10]!;
      final cellCount = raw[114]!;
      expect(cellUvp, 2600);
      expect(cellCount, 16);

      // Bind the schema and convert to user units exactly like the service.
      final schema = BmsParameterSchema.forBrand(BmsBrand.jkbms)!;
      final p = schema.firstWhere((p) => p.jkFrameOffset == 10);
      expect(p.jkRawFactor, 0.001);
      expect(cellUvp * p.jkRawFactor, closeTo(2.6, 0.0001));
      // The cell-count parameter reads the single raw byte directly.
      final cellCountP = schema.firstWhere((p) => p.jkFrameOffset == 114);
      expect(cellCountP.jkRawFactor, 1.0);
    });

    test('KS write command frame layout is exact', () {
      expect(BmsProtocolHelper.buildKsWriteCommand(0x10, 0x1234),
          [0x7B, 0x10, 0x02, 0x12, 0x34, 0x7D]);
    });

    test('KS settings request iterates the four config frame types', () {
      final requests = BmsProtocolHelper.buildKsSettingsRequests();
      expect(requests.length, 4);
      expect(requests.every((r) => r.length >= 3 && r[0] == 0x7B), isTrue);
    });
  });
}

void _writeU32(List<int> frame, int offset, int value) {
  frame[offset] = value & 0xFF;
  frame[offset + 1] = (value >> 8) & 0xFF;
  frame[offset + 2] = (value >> 16) & 0xFF;
  frame[offset + 3] = (value >> 24) & 0xFF;
}