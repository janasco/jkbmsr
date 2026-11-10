import 'package:flutter_test/flutter_test.dart';

import 'package:jkbmsr_pro/features/alerts/event_log.dart';
import 'package:jkbmsr_pro/models/alert.dart';
import 'package:jkbmsr_pro/models/ble_history_event.dart';
import 'package:jkbmsr_pro/models/ota_event.dart';

Alert _alert(
  String id, {
  String message = 'Cell voltage low',
  String severity = 'warning',
  String createdAt = '2026-09-01 09:00:00',
  String? resolvedAt = '2026-09-01 09:30:00',
}) {
  return Alert(
    id: id,
    deviceId: 'gw-1',
    deviceName: 'Home Battery',
    severity: severity,
    message: message,
    createdAt: createdAt,
    isResolved: true,
    resolvedAt: resolvedAt,
  );
}

BleSessionRecord _ble(
  String timestamp, {
  String deviceId = 'gw-1',
  String deviceName = 'Home Battery',
  String address = 'AA:BB:CC:DD:EE:FF',
  String advertisedName = 'JK-BMS',
  int rssi = -61,
  String hardware = '11A',
  String software = '11.55',
  int frames = 42,
  bool readOnly = true,
}) {
  return BleSessionRecord(
    deviceId: deviceId,
    deviceName: deviceName,
    event: BleHistoryEvent(
      timestamp: timestamp,
      address: address,
      advertisedName: advertisedName,
      rssi: rssi,
      hardwareVersion: hardware,
      softwareVersion: software,
      framesDecoded: frames,
      readOnly: readOnly,
    ),
  );
}

OtaEventRecord _ota(
  String createdAt, {
  int id = 1,
  String deviceId = 'gw-1',
  String deviceName = 'Home Battery',
  String lastResult = 'success',
  String offeredVersion = '0.9.10',
  bool checkSucceeded = true,
  bool available = false,
  bool applied = false,
}) {
  return OtaEventRecord(
    deviceId: deviceId,
    deviceName: deviceName,
    event: OtaEvent(
      id: id,
      lastResult: lastResult,
      offeredVersion: offeredVersion,
      lastCheckSucceeded: checkSucceeded,
      updateAvailable: available,
      updateApplied: applied,
      createdAt: createdAt,
    ),
  );
}

void main() {
  group('parseEventLogTime', () {
    test('reads the API\'s zone-less format as UTC', () {
      final parsed = parseEventLogTime('2026-09-01 10:00:00');
      expect(parsed, isNotNull);
      expect(parsed!.toUtc(), DateTime.utc(2026, 9, 1, 10));
    });

    test('keeps an explicit zone', () {
      final parsed = parseEventLogTime('2026-09-01T12:00:00Z');
      expect(parsed!.toUtc(), DateTime.utc(2026, 9, 1, 12));
    });

    test('returns null rather than inventing a time', () {
      expect(parseEventLogTime(''), isNull);
      expect(parseEventLogTime('not a date'), isNull);
    });

    test('display falls back to the raw value', () {
      expect(formatEventLogTime(''), 'Time unknown');
      expect(formatEventLogTime('not a date'), 'not a date');
    });
  });

  group('buildEventLog', () {
    test('merges every source newest first', () {
      final entries = buildEventLog(
        resolvedAlerts: [_alert('a1')],
        bleSessions: [_ble('2026-09-01T12:00:00Z')],
        otaEvents: [_ota('2026-09-01 11:00:00')],
      );

      expect(entries.map((e) => e.kind), [
        EventKind.bleSession,
        EventKind.otaUpdate,
        EventKind.alert,
      ]);
    });

    test('an unparseable timestamp sorts last instead of counting as oldest', () {
      final entries = buildEventLog(
        resolvedAlerts: [
          _alert('a1', resolvedAt: 'garbage'),
          _alert('a2', resolvedAt: '2026-09-01 10:00:00'),
        ],
        bleSessions: const [],
        otaEvents: const [],
      );

      expect(entries.first.id, 'alert:a2');
      expect(entries.last.rawTimestamp, 'garbage');
      expect(entries.last.occurredAt, isNull);
    });

    test('an alert entry is stamped when it resolved and carries its detail', () {
      final entry = buildEventLog(
        resolvedAlerts: [
          _alert('a1', message: 'Pack over-voltage', severity: 'critical')
        ],
        bleSessions: const [],
        otaEvents: const [],
      ).single;

      expect(entry.summary, 'Pack over-voltage');
      expect(entry.severity, 'critical');
      expect(entry.rawTimestamp, '2026-09-01 09:30:00');
      expect(
        entry.fields.map((f) => f.label),
        containsAll(['Severity', 'Message', 'Gateway', 'Raised', 'Resolved']),
      );
      expect(entry.alert?.id, 'a1');
    });

    test('a BLE session summarises the connection and keeps its readings', () {
      final entry = buildEventLog(
        resolvedAlerts: const [],
        bleSessions: [_ble('2026-09-01T12:00:00Z', frames: 1)],
        otaEvents: const [],
      ).single;

      expect(entry.summary, 'Connected to JK-BMS · 1 frame decoded');
      final values = {for (final f in entry.fields) f.label: f.value};
      expect(values['Address'], 'AA:BB:CC:DD:EE:FF');
      expect(values['Signal'], '-61 dBm');
      expect(values['Hardware'], '11A');
      expect(values['Firmware'], '11.55');
      expect(values['Frames decoded'], '1');
      expect(values['Access'], 'Read-only');
    });

    test('a BLE session with no RSSI reading says unknown, not -128', () {
      final entry = buildEventLog(
        resolvedAlerts: const [],
        bleSessions: [_ble('2026-09-01T12:00:00Z', rssi: -128)],
        otaEvents: const [],
      ).single;

      final values = {for (final f in entry.fields) f.label: f.value};
      expect(values['Signal'], 'Unknown');
    });

    test('OTA summaries distinguish applied, offered and failed', () {
      final applied = buildEventLog(
        resolvedAlerts: const [],
        bleSessions: const [],
        otaEvents: [_ota('2026-09-01 10:00:00', applied: true, available: true)],
      ).single;
      expect(applied.summary, 'Firmware updated to 0.9.10');

      final offered = buildEventLog(
        resolvedAlerts: const [],
        bleSessions: const [],
        otaEvents: [_ota('2026-09-01 10:00:00', available: true)],
      ).single;
      expect(offered.summary, 'Firmware 0.9.10 is available');

      final failed = buildEventLog(
        resolvedAlerts: const [],
        bleSessions: const [],
        otaEvents: [
          _ota('2026-09-01 10:00:00',
              checkSucceeded: false, lastResult: 'failed')
        ],
      ).single;
      expect(failed.summary, 'Firmware update check failed');

      final current = buildEventLog(
        resolvedAlerts: const [],
        bleSessions: const [],
        otaEvents: [_ota('2026-09-01 10:00:00', lastResult: 'idle')],
      ).single;
      expect(current.summary, 'Update check found no new firmware');
    });

    test('empty sources produce an empty log, not a placeholder row', () {
      final entries = buildEventLog(
        resolvedAlerts: const [],
        bleSessions: const [],
        otaEvents: const [],
      );
      expect(entries, isEmpty);
    });
  });
}
