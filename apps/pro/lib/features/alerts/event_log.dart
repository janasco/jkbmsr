import '../../models/alert.dart';
import '../../models/ble_history_event.dart';
import '../../models/ota_event.dart';

/// What produced one entry in the event log. Kept separate from the alert
/// severity because an unresolved alarm, a gateway connection and a firmware
/// update are different kinds of fact even when they share a timeline.
enum EventKind { alert, bleSession, otaUpdate }

/// A labelled value shown when an entry is expanded. Labels are short and
/// values are rendered on their own line so long addresses, versions and
/// messages have somewhere to go at large OS text scales.
class EventLogField {
  final String label;
  final String value;
  final bool mono;

  const EventLogField(this.label, this.value, {this.mono = false});
}

/// One row of the log: when it happened, what it was, and everything the
/// source knew about it.
class EventLogEntry {
  final String id;
  final EventKind kind;
  final String rawTimestamp;
  final DateTime? occurredAt;
  final String summary;

  /// Only set for [EventKind.alert]; drives the marker colour.
  final String? severity;

  /// Only set for [EventKind.alert]; lets the log offer permanent deletion
  /// for exactly the entries the API can delete.
  final Alert? alert;

  final List<EventLogField> fields;

  const EventLogEntry({
    required this.id,
    required this.kind,
    required this.rawTimestamp,
    required this.occurredAt,
    required this.summary,
    this.severity,
    this.alert,
    required this.fields,
  });
}

/// A BLE history row together with the gateway it belongs to: the endpoint is
/// per-device and the row itself carries no gateway name.
class BleSessionRecord {
  final String deviceId;
  final String deviceName;
  final BleHistoryEvent event;

  const BleSessionRecord({
    required this.deviceId,
    required this.deviceName,
    required this.event,
  });
}

/// An OTA history row together with the gateway it belongs to.
class OtaEventRecord {
  final String deviceId;
  final String deviceName;
  final OtaEvent event;

  const OtaEventRecord({
    required this.deviceId,
    required this.deviceName,
    required this.event,
  });
}

/// Parses the timestamps the dashboard endpoints send. Alerts and OTA rows
/// arrive as `YYYY-MM-DD HH:mm:ss` with no zone (UTC server time); BLE rows
/// arrive as ISO-8601. A value that cannot be parsed returns null rather than
/// a fabricated time, and such an entry sorts last instead of pretending to
/// be the oldest thing that ever happened.
DateTime? parseEventLogTime(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  var normalized = text;
  if (normalized.contains(' ') && !normalized.contains('T')) {
    normalized = normalized.replaceFirst(' ', 'T');
  }
  final hasZone = normalized.endsWith('Z') ||
      RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(normalized);
  if (!hasZone) normalized = '${normalized}Z';
  return DateTime.tryParse(normalized);
}

/// Human-readable local time for an entry header; falls back to the source
/// string when it could not be parsed so nothing is silently dropped.
String formatEventLogTime(String raw) {
  final parsed = parseEventLogTime(raw);
  if (parsed == null) return raw.trim().isEmpty ? 'Time unknown' : raw;
  final local = parsed.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// Builds the single newest-first timeline from three independent sources.
/// Sources are merged here rather than in the widget so the ordering and the
/// summaries can be exercised without a widget tree.
List<EventLogEntry> buildEventLog({
  required List<Alert> resolvedAlerts,
  required List<BleSessionRecord> bleSessions,
  required List<OtaEventRecord> otaEvents,
}) {
  final entries = <EventLogEntry>[];
  final sequence = <String, int>{};

  void add(EventLogEntry entry) {
    sequence[entry.id] = entries.length;
    entries.add(entry);
  }

  for (final alert in resolvedAlerts) {
    add(_alertEntry(alert));
  }
  for (var i = 0; i < bleSessions.length; i++) {
    add(_bleEntry(bleSessions[i], i));
  }
  for (final record in otaEvents) {
    add(_otaEntry(record));
  }

  entries.sort((a, b) {
    final aTime = a.occurredAt;
    final bTime = b.occurredAt;
    if (aTime == null && bTime == null) {
      return sequence[a.id]!.compareTo(sequence[b.id]!);
    }
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    final byTime = bTime.compareTo(aTime);
    if (byTime != 0) return byTime;
    return sequence[a.id]!.compareTo(sequence[b.id]!);
  });

  return entries;
}

EventLogEntry _alertEntry(Alert alert) {
  final severity = alert.severity.toLowerCase();
  final fields = <EventLogField>[
    EventLogField('Severity', _capitalize(severity)),
    EventLogField('Message', alert.message.isEmpty ? '-' : alert.message),
    EventLogField('Gateway', alert.deviceName.isEmpty ? '-' : alert.deviceName),
    EventLogField('Raised', formatEventLogTime(alert.createdAt)),
  ];
  if (alert.resolvedAt != null && alert.resolvedAt!.trim().isNotEmpty) {
    fields.add(EventLogField('Resolved', formatEventLogTime(alert.resolvedAt!)));
  }
  if (alert.id.isNotEmpty) {
    fields.add(EventLogField('Alert ID', '#${alert.id}', mono: true));
  }

  return EventLogEntry(
    id: 'alert:${alert.id}',
    kind: EventKind.alert,
    rawTimestamp: alert.resolvedAt ?? alert.createdAt,
    occurredAt: parseEventLogTime(alert.resolvedAt ?? alert.createdAt),
    summary: alert.message.isEmpty ? 'Alarm resolved' : alert.message,
    severity: severity,
    alert: alert,
    fields: fields,
  );
}

EventLogEntry _bleEntry(BleSessionRecord record, int index) {
  final event = record.event;
  final name = event.advertisedName.isEmpty ? 'JK-BMS' : event.advertisedName;
  final frames = event.framesDecoded == 1 ? '1 frame' : '${event.framesDecoded} frames';
  final gateway = record.deviceName.isNotEmpty
      ? record.deviceName
      : (record.deviceId.isNotEmpty ? record.deviceId : '-');

  return EventLogEntry(
    id: 'ble:${record.deviceId}:$index:${event.timestamp}',
    kind: EventKind.bleSession,
    rawTimestamp: event.timestamp,
    occurredAt: parseEventLogTime(event.timestamp),
    summary: 'Connected to $name · $frames decoded',
    fields: [
      EventLogField('Gateway', gateway),
      EventLogField(
        'Address',
        event.address.isEmpty ? 'Automatic' : event.address,
        mono: true,
      ),
      EventLogField(
        'Advertised name',
        event.advertisedName.isEmpty ? '-' : event.advertisedName,
      ),
      EventLogField(
        'Signal',
        event.rssi > -128 ? '${event.rssi} dBm' : 'Unknown',
        mono: true,
      ),
      EventLogField(
        'Hardware',
        event.hardwareVersion.isEmpty ? '-' : event.hardwareVersion,
        mono: true,
      ),
      EventLogField(
        'Firmware',
        event.softwareVersion.isEmpty ? '-' : event.softwareVersion,
        mono: true,
      ),
      EventLogField('Frames decoded', '${event.framesDecoded}', mono: true),
      EventLogField(
        'Access',
        event.readOnly ? 'Read-only' : 'Read and write',
      ),
    ],
  );
}

EventLogEntry _otaEntry(OtaEventRecord record) {
  final event = record.event;
  final version = event.offeredVersion;
  final String summary;
  if (event.updateApplied) {
    summary = version.isEmpty
        ? 'Firmware update applied'
        : 'Firmware updated to $version';
  } else if (event.updateAvailable) {
    summary = version.isEmpty
        ? 'A firmware update is available'
        : 'Firmware $version is available';
  } else if (!event.lastCheckSucceeded) {
    summary = 'Firmware update check failed';
  } else {
    summary = 'Update check found no new firmware';
  }

  final gateway = record.deviceName.isNotEmpty
      ? record.deviceName
      : (record.deviceId.isNotEmpty ? record.deviceId : '-');

  return EventLogEntry(
    id: 'ota:${record.deviceId}:${event.id}:${event.createdAt}',
    kind: EventKind.otaUpdate,
    rawTimestamp: event.createdAt,
    occurredAt: parseEventLogTime(event.createdAt),
    summary: summary,
    fields: [
      EventLogField('Gateway', gateway),
      EventLogField(
        'Result',
        event.lastResult.isEmpty ? '-' : _capitalize(event.lastResult),
      ),
      EventLogField('Offered version', version.isEmpty ? '-' : version, mono: true),
      EventLogField('Check succeeded', event.lastCheckSucceeded ? 'Yes' : 'No'),
      EventLogField('Update available', event.updateAvailable ? 'Yes' : 'No'),
      EventLogField('Update applied', event.updateApplied ? 'Yes' : 'No'),
    ],
  );
}

String _capitalize(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}
