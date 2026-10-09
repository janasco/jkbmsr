import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/bms_models.dart';
import '../protocols/bms_protocol.dart';

/// One logbook event as the app keeps it on disk.
///
/// The BMS sends no absolute wall-clock time — only a seconds offset, which is
/// formatted `DdHHhMMmSSs` exactly as the `syssi/esphome-jk-bms` reference does.
/// [firstSeen] is when *this app* observed the entry, kept as honest local
/// metadata rather than pretending the hardware timestamp is a calendar date.
@immutable
class LogbookRecord {
  /// Seconds offset as sent on the wire (the u32 LE at the head of each entry).
  final int seconds;

  /// Event code byte, the final byte of each 5-byte entry.
  final int code;

  /// When this app first stored the entry (local clock).
  final DateTime firstSeen;

  const LogbookRecord({
    required this.seconds,
    required this.code,
    required this.firstSeen,
  });

  /// Human-readable event name from the syssi `LOGBOOK_CODES` table. Empty for
  /// undocumented codes; the UI then shows `unknown event (0xNN)`.
  String get name => BmsProtocolHelper.jk02LogbookCodeName(code);

  /// Stable de-duplication identity. Two entries are the same event iff they
  /// share both their seconds offset and their event code.
  String get key => '$seconds:$code';

  /// `Dd HHh MMm SSs` relative offset, identical in shape to the reference.
  String get offsetLabel => formatOffset(seconds);

  Map<String, dynamic> toJson() => {
        'seconds': seconds,
        'code': code,
        'firstSeen': firstSeen.toUtc().toIso8601String(),
      };

  factory LogbookRecord.fromJson(Map<String, dynamic> json) => LogbookRecord(
        seconds: (json['seconds'] as num).toInt(),
        code: (json['code'] as num).toInt(),
        firstSeen:
            DateTime.tryParse(json['firstSeen'] as String? ?? '')?.toLocal() ??
                DateTime.fromMillisecondsSinceEpoch(0),
      );

  /// `Dd HHh MMm SSs`, the reference's own presentation of the seconds offset.
  static String formatOffset(int seconds) {
    final d = seconds ~/ 86400;
    final rem = seconds % 86400;
    final h = rem ~/ 3600;
    final m = (rem % 3600) ~/ 60;
    final s = rem % 60;
    return '${d}d ${h.toString().padLeft(2, '0')}h '
        '${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
  }

  @override
  bool operator ==(Object other) =>
      other is LogbookRecord && other.seconds == seconds && other.code == code;

  @override
  int get hashCode => Object.hash(seconds, code);

  @override
  String toString() => 'LogbookRecord($seconds, 0x${code.toRadixString(16)})';
}

/// Local, app-side store of every logbook entry the app has ever seen for a
/// device — so the list grows beyond what one BMS fetch can return and stays
/// browsable offline.
///
/// **Why accumulating is the only way to "fetch the full logbook".** The JK-BMS
/// `0xA1` request is answered with a single fixed 300-byte `0x05` frame, and the
/// reference implementation (`syssi/esphome-jk-bms`, `decode_logbook_`) decodes
/// at most **50** entries from it (`for i < log_count && i < 50`). There is no
/// offset/start-index field in the command — `button/__init__.py` sends
/// `CONF_RETRIEVE_LOGBOOK = 0xA1` with a zero value and no paging — so the
/// hardware cannot be asked for entries 51..N. What it *can* do is report, at
/// frame offset 6, a total `log_count` that may exceed 50 while carrying only
/// the newest 50. Re-fetching over time and unioning the windows is therefore
/// what grows the local history; there is no invented paging command here.
///
/// Storage is one JSON file per device under the app support directory — the
/// lightest option that survives restarts and is trivial to inspect. The app
/// already depends on `path_provider`; no database is added for this.
class LogbookStore {
  LogbookStore({Future<Directory> Function()? directoryProvider})
      : _directoryProvider = directoryProvider ?? _defaultDirectory,
        _inMemory = false;

  /// Process-wide store used by the UI and the BLE service.
  static final LogbookStore instance = LogbookStore();

  /// Test-only constructor: keeps everything in memory and never touches disk,
  /// so widget tests can drive pagination without real file IO under the test
  /// binding's fake clock.
  @visibleForTesting
  LogbookStore.inMemory()
      : _directoryProvider = _unavailableDirectory,
        _inMemory = true;

  final Future<Directory> Function() _directoryProvider;
  final bool _inMemory;
  final Map<String, List<LogbookRecord>> _cache = {};

  final StreamController<String> _changes = StreamController<String>.broadcast();

  /// Emits a device id whenever its stored set gained at least one entry (or
  /// was cleared), so an open screen can reload. Broadcast and never closed:
  /// the store is a process-wide singleton.
  Stream<String> get changes => _changes.stream;

  static Future<Directory> _defaultDirectory() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/logbooks');
  }

  static Future<Directory> _unavailableDirectory() async =>
      throw StateError('logbook store is in-memory');

  /// A filesystem-safe file name for [deviceId]. BLE ids are MAC-shaped
  /// (`AA:BB:CC:DD:EE:FF`); everything outside a conservative set becomes `_`,
  /// so a device id can never escape the logbook directory.
  static String fileNameFor(String deviceId) {
    final safe = deviceId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.isEmpty ? 'unknown' : safe;
  }

  Future<File> _fileFor(String deviceId) async {
    final dir = await _directoryProvider();
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/${fileNameFor(deviceId)}.json');
  }

  /// Loads the stored records for [deviceId] in insertion (observation) order,
  /// oldest first. Cached after the first read.
  Future<List<LogbookRecord>> load(String deviceId) async {
    final cached = _cache[deviceId];
    if (cached != null) return cached;

    var records = <LogbookRecord>[];
    if (!_inMemory) {
      try {
        final file = await _fileFor(deviceId);
        if (await file.exists()) {
          final raw = await file.readAsString();
          if (raw.trim().isNotEmpty) {
            final decoded = json.decode(raw);
            final entries = decoded is Map
                ? (decoded['entries'] as List? ?? const [])
                : (decoded as List);
            records = entries
                .whereType<Map>()
                .map((e) => LogbookRecord.fromJson(e.cast<String, dynamic>()))
                .toList();
          }
        }
      } catch (_) {
        // A corrupt or unreadable file must not crash the UI: start empty.
        records = <LogbookRecord>[];
      }
    }
    _cache[deviceId] = records;
    return records;
  }

  Future<int> count(String deviceId) async => (await load(deviceId)).length;

  /// Merges [incoming] into the stored set, de-duplicated by [LogbookRecord.key]
  /// and preserving observation order. Returns the new total. Persists and
  /// emits a change only when something was actually added.
  Future<int> merge(String deviceId, Iterable<LogbookRecord> incoming) async {
    final existing = await load(deviceId);
    final merged = mergeRecords(existing, incoming);
    if (merged.length == existing.length) return existing.length;
    _cache[deviceId] = merged;
    await _persist(deviceId, merged);
    _changes.add(deviceId);
    return merged.length;
  }

  /// Convenience for a freshly received BMS logbook frame.
  Future<int> mergeLogbook(String deviceId, Jk02Logbook logbook) {
    final now = DateTime.now();
    return merge(deviceId, [
      for (final entry in logbook.entries)
        LogbookRecord(seconds: entry.seconds, code: entry.code, firstSeen: now),
    ]);
  }

  Future<void> _persist(String deviceId, List<LogbookRecord> records) async {
    if (_inMemory) return;
    try {
      final file = await _fileFor(deviceId);
      final payload = json.encode({
        'version': 1,
        'deviceId': deviceId,
        'entries': [for (final r in records) r.toJson()],
      });
      await file.writeAsString(payload, flush: true);
    } catch (_) {
      // Best-effort: the in-memory list still serves this session.
    }
  }

  /// Returns one page of the newest-first view, for lazy loading. [offset] is
  /// measured from the newest entry.
  Future<List<LogbookRecord>> readPage(
    String deviceId, {
    required int offset,
    required int limit,
  }) async {
    final oldestFirst = await load(deviceId);
    final newestFirst = oldestFirst.reversed.toList(growable: false);
    return page(newestFirst, offset: offset, limit: limit);
  }

  /// Deletes the stored file and clears the in-memory cache for [deviceId].
  Future<void> clear(String deviceId) async {
    _cache[deviceId] = <LogbookRecord>[];
    if (!_inMemory) {
      try {
        final file = await _fileFor(deviceId);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    _changes.add(deviceId);
  }

  // ── Pure logic (unit-tested without any IO) ──────────────────────────────

  /// Unions [existing] and [incoming], dropping entries whose [LogbookRecord.key]
  /// was already present and preserving order (so a re-fetch of the same frame
  /// adds nothing, and new events append).
  static List<LogbookRecord> mergeRecords(
    List<LogbookRecord> existing,
    Iterable<LogbookRecord> incoming,
  ) {
    final seen = <String>{for (final e in existing) e.key};
    final out = List<LogbookRecord>.of(existing);
    for (final e in incoming) {
      if (seen.add(e.key)) out.add(e);
    }
    return out;
  }

  /// A clamped page slice. `offset < 0`, `limit <= 0` or an offset past the end
  /// yield an empty list; the final page is truncated rather than throwing.
  static List<T> page<T>(List<T> items, {required int offset, required int limit}) {
    if (offset < 0 || limit <= 0 || offset >= items.length) return <T>[];
    final end = offset + limit;
    return items.sublist(offset, end > items.length ? items.length : end);
  }
}
