import 'dart:convert';
import 'dart:math';

import 'package:bms_core/bms_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_contributor/models/contribution.dart';

import '../support/jk02_fixtures.dart';

/// Device info decoded from the captured 24S fixture.
BmsModelInfo deviceInfo24s() =>
    BmsProtocolHelper.parseJk02DeviceInfoFrame(bytesFromHex(devInfo24sHex))!;

String withVersion(String doc, String version) {
  final map = jsonDecode(doc) as Map<String, dynamic>;
  map['schemaVersion'] = version;
  return jsonEncode(map);
}

void main() {
  group('Contribution round-trip', () {
    test('encode -> decode -> encode is byte-identical', () {
      final original = sampleContribution();
      final encoded = original.encode();

      final decoded = Contribution.decode(encoded);
      expect(decoded.encode(), encoded);
    });

    test('every section survives a round-trip', () {
      final original = Contribution.fromCapture(
        app: const AppProvenance(version: '0.1.0+1', platform: 'android', osVersion: '34'),
        remoteId: 'AA:BB:CC:11:22:33',
        advertisedName: 'JK_B2A24S15P',
        rssi: -63,
        serviceUuids: const ['0000ffe0-0000-1000-8000-00805f9b34fb'],
        deviceInfo: null,
        is32s: true,
        samples: const [],
        rawFrames: const [
          RawFrame(dir: 'rx', tOffsetMs: 0, hex: '55aa', frameType: 'deviceInfo'),
        ],
        consent: ConsentRecord(
          givenAt: DateTime.utc(2026, 10, 13, 8),
          scope: 'telemetry+frames',
        ),
        settingsValues: const {'cellOvp': 3.55},
        settingsCapturedAt: DateTime.utc(2026, 10, 14, 9, 21),
        logbookEntries: const [LogbookCaptureEntry(seconds: 238, code: 0x44)],
        contributionId: 'c_01926f6a-1c00-7000-8000-0000000000ab',
        capturedAt: DateTime.utc(2026, 10, 13, 9, 20),
      );

      final decoded = Contribution.decode(original.encode());
      expect(decoded.schemaVersion, Contribution.currentSchemaVersion);
      expect(decoded.consent!.scope, 'telemetry+frames');
      expect(decoded.settings!.values['cellOvp'], 3.55);
      expect(decoded.settings!.capturedAt, DateTime.utc(2026, 10, 14, 9, 21));
      expect(decoded.logbook!.entries.single.code, 0x44);
      expect(decoded.rawFrames.single.frameType, 'deviceInfo');
      expect(decoded.bms.layout, 'JK02_32S');
    });

    test('the JSON carries a measured sizeBytes', () {
      final json = sampleContribution().toJson();
      expect(json['sizeBytes'], isA<int>());
      expect(json['sizeBytes'] as int, greaterThan(0));
    });
  });

  group('schemaVersion handling', () {
    test('the client writes its own current version', () {
      final json = jsonDecode(sampleContribution().encode()) as Map<String, dynamic>;
      expect(json['schemaVersion'], '1');
    });

    test('additive-minor 1.x documents are accepted', () {
      final doc = withVersion(sampleContribution().encode(), '1.4');
      expect(Contribution.decode(doc).schemaVersion, '1.4');
      // Re-encoding writes the client's own version, per plan §4.
      expect(Contribution.decode(doc).toJson()['schemaVersion'], '1');
    });

    test('an unknown major is rejected', () {
      final doc = withVersion(sampleContribution().encode(), '2');
      expect(() => Contribution.decode(doc), throwsA(isA<UnsupportedSchemaVersion>()));
    });

    test('a missing or empty version is rejected as malformed', () {
      final map = jsonDecode(sampleContribution().encode()) as Map<String, dynamic>;
      map.remove('schemaVersion');
      expect(() => Contribution.fromJson(map), throwsA(isA<FormatException>()));

      map['schemaVersion'] = '';
      expect(() => Contribution.fromJson(map), throwsA(isA<FormatException>()));
    });

    test('isSupportedSchemaVersion matches the major rule', () {
      for (final v in ['1', '1.0', '1.9']) {
        expect(Contribution.isSupportedSchemaVersion(v), isTrue, reason: v);
      }
      for (final v in ['', '0', '2', 'x', '10']) {
        expect(Contribution.isSupportedSchemaVersion(v), isFalse, reason: v);
      }
    });
  });

  group('anonymisation defaults', () {
    test('serial is withheld and redaction says so', () {
      final c = sampleContribution();
      expect(c.bms.serialHash, isNull);
      expect(c.redaction.serialNumber, 'withheld');
    });

    test('opting in carries the serial and marks it shared', () {
      final c = Contribution.fromCapture(
        app: const AppProvenance(version: '0.1.0+1', platform: 'android', osVersion: '34'),
        remoteId: 'AA:BB:CC:11:22:33',
        advertisedName: 'JK_B2A24S15P',
        rssi: -63,
        serviceUuids: const [],
        deviceInfo: deviceInfo24s(),
        is32s: false,
        samples: const [],
        includeSerial: true,
        contributionId: 'c_01926f6a-1c00-7000-8000-000000000002',
        capturedAt: DateTime.utc(2026, 10, 14),
      );
      expect(c.bms.serialHash, '2021602096');
      expect(c.redaction.serialNumber, 'shared');
    });

    test('manufacturing date is truncated to a year-month', () {
      expect(sampleContribution().bms.manufacturingYearMonth, '2022-04');
    });

    test('power-on count and RSSI are bucketed, never exact', () {
      final c = sampleContribution();
      expect(c.bms.powerOnCountBucket, '1-9'); // fixture reports 6
      expect(c.advertisement.rssiBucket, '-70..-60'); // fixture rssi -63
    });

    test('the Bluetooth address keeps only the vendor OUI', () {
      expect(sampleContribution().advertisement.addressMasked, 'AA:BB:CC:00:00:00');
    });

    test('the advertised name is reduced to a prefix plus wildcard', () {
      expect(sampleContribution().advertisement.namePattern, 'JK_*');
    });

    test('the contribution id is a fresh UUIDv7, not device-derived', () {
      final generated = Contribution.fromCapture(
        app: const AppProvenance(version: '0.1.0+1', platform: 'android', osVersion: '34'),
        remoteId: 'AA:BB:CC:11:22:33',
        advertisedName: 'x',
        rssi: -50,
        serviceUuids: const [],
        deviceInfo: null,
        is32s: false,
        samples: const [],
      );
      expect(generated.contributionId, startsWith('c_'));
      final uuid = generated.contributionId.substring(2);
      expect(uuid.length, 36);
      expect(uuid[14], '7'); // version nibble
      expect('89ab'.contains(uuid[19]), isTrue); // RFC 9562 variant
      expect(generated.contributionId, isNot(sampleContribution().contributionId));
    });

    test('the payload contains no user identifiers', () {
      final json = sampleContribution().toJson();
      for (final forbidden in ['name', 'email', 'phone', 'location', 'userId', 'mac']) {
        expect(json.containsKey(forbidden), isFalse, reason: 'unexpected key: $forbidden');
      }
    });

    test('machine identity is absent: iOS UUIDs are never emitted as a MAC', () {
      expect(Contribution.maskMac('e006b3a7-ef7b-4980-a668-1f8005f84383'), isNull);
    });
  });

  group('anonymisation helpers', () {
    test('uuidV7 is deterministic for an injected clock and Random', () {
      final a = Contribution.uuidV7(
        now: DateTime.utc(2026, 10, 14, 9, 20),
        random: Random(1),
      );
      final b = Contribution.uuidV7(
        now: DateTime.utc(2026, 10, 14, 9, 20),
        random: Random(1),
      );
      expect(a, b);
      expect(a[14], '7');
    });

    test('bucketPowerOnCount boundaries', () {
      expect(Contribution.bucketPowerOnCount(0), '0');
      expect(Contribution.bucketPowerOnCount(1), '1-9');
      expect(Contribution.bucketPowerOnCount(9), '1-9');
      expect(Contribution.bucketPowerOnCount(10), '10-99');
      expect(Contribution.bucketPowerOnCount(999), '100-999');
      expect(Contribution.bucketPowerOnCount(1000), '1000-9999');
      expect(Contribution.bucketPowerOnCount(50000), '10000+');
    });

    test('bucketRssi rounds down into 10 dBm bands', () {
      expect(Contribution.bucketRssi(-65), '-70..-60');
      expect(Contribution.bucketRssi(-70), '-70..-60');
      expect(Contribution.bucketRssi(-60), '-60..-50');
    });

    test('yearMonth truncates and rejects unknown', () {
      expect(Contribution.yearMonth('2022-04-07'), '2022-04');
      expect(Contribution.yearMonth('2024-06'), '2024-06');
      expect(Contribution.yearMonth(''), isNull);
      expect(Contribution.yearMonth('unknown'), isNull);
    });

    test('maskMac normalises separators and zeroes the host part', () {
      expect(Contribution.maskMac('aa-bb-cc-11-22-33'), 'AA:BB:CC:00:00:00');
      expect(Contribution.maskMac('AA:BB:CC:11:22:33'), 'AA:BB:CC:00:00:00');
      expect(Contribution.maskMac('not-a-mac'), isNull);
    });

    test('namePattern keeps three characters', () {
      expect(Contribution.namePattern('JK_B2A24S15P'), 'JK_*');
      expect(Contribution.namePattern('JK'), 'JK*');
      expect(Contribution.namePattern('  '), '(unnamed)');
    });
  });

  group('size discipline', () {
    test('raw frames are capped to the newest 200', () {
      final frames = List<RawFrame>.generate(
        250,
        (i) => RawFrame(dir: 'rx', tOffsetMs: i, hex: 'aa', frameType: 'cellInfo'),
      );
      final c = Contribution.fromCapture(
        app: const AppProvenance(version: '0.1.0+1', platform: 'android', osVersion: '34'),
        remoteId: 'AA:BB:CC:11:22:33',
        advertisedName: 'x',
        rssi: -50,
        serviceUuids: const [],
        deviceInfo: null,
        is32s: false,
        samples: const [],
        rawFrames: frames,
      );
      expect(c.rawFrames.length, Contribution.maxRawFrames);
      // The newest are kept: the last generated frame (offset 249) survives.
      expect(c.rawFrames.last.tOffsetMs, 249);
      expect(c.rawFrames.first.tOffsetMs, 50);
    });
  });
}
