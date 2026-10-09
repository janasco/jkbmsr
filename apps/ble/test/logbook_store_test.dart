import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/services/logbook_store.dart';

LogbookRecord rec(int seconds, int code) =>
    LogbookRecord(seconds: seconds, code: code, firstSeen: DateTime.utc(2026, 1, 1));

void main() {
  group('mergeRecords (de-dup + ordering)', () {
    test('drops entries already present and appends genuinely new ones', () {
      final merged = LogbookStore.mergeRecords(
        [rec(0, 0x01), rec(5, 0x02)],
        [rec(5, 0x02), rec(9, 0x03)],
      );
      expect(merged.map((e) => e.key).toList(), ['0:1', '5:2', '9:3']);
    });

    test('re-merging the same frame adds nothing (stable size)', () {
      final once = LogbookStore.mergeRecords(
        [rec(0, 0x01), rec(5, 0x02)],
        [rec(0, 0x01), rec(5, 0x02)],
      );
      final twice = LogbookStore.mergeRecords(once, [rec(0, 0x01), rec(5, 0x02)]);
      expect(twice.length, 2);
    });

    test('same seconds offset but different code are distinct events', () {
      final merged = LogbookStore.mergeRecords([rec(0, 0x01)], [rec(0, 0x02)]);
      expect(merged.length, 2);
    });

    test('preserves existing order and appends in incoming order', () {
      final merged = LogbookStore.mergeRecords(
        [rec(100, 0x01)],
        [rec(200, 0x02), rec(50, 0x03)],
      );
      expect(merged.map((e) => e.seconds).toList(), [100, 200, 50]);
    });
  });

  group('page (pagination boundaries)', () {
    final items = List<int>.generate(125, (i) => i);

    test('first page is exactly limit items', () {
      expect(LogbookStore.page(items, offset: 0, limit: 50),
          List<int>.generate(50, (i) => i));
    });

    test('final page is truncated to the remaining items', () {
      expect(LogbookStore.page(items, offset: 100, limit: 50),
          List<int>.generate(25, (i) => 100 + i));
    });

    test('an offset at or past the end yields nothing', () {
      expect(LogbookStore.page(items, offset: 125, limit: 50), isEmpty);
      expect(LogbookStore.page(items, offset: 999, limit: 50), isEmpty);
    });

    test('a non-positive limit or negative offset yields nothing', () {
      expect(LogbookStore.page(items, offset: 0, limit: 0), isEmpty);
      expect(LogbookStore.page(items, offset: -1, limit: 50), isEmpty);
    });
  });

  group('LogbookStore.fileNameFor', () {
    test('sanitizes a MAC-shaped BLE id into one safe file name', () {
      final name = LogbookStore.fileNameFor('AA:BB:CC:DD:EE:FF');
      expect(name.contains('/'), isFalse);
      expect(name.contains(':'), isFalse);
    });

    test('an empty id still yields a usable name', () {
      expect(LogbookStore.fileNameFor(''), 'unknown');
    });
  });

  group('LogbookStore disk round-trip', () {
    late Directory dir;
    late LogbookStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('jkbmsr_logbook_test');
      store = LogbookStore(directoryProvider: () async => dir);
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('persists merged records and a second store reads them back', () async {
      final n = await store.merge('dev', [rec(0, 0x01), rec(5, 0x02), rec(9, 0x03)]);
      expect(n, 3);

      // A fresh instance (simulating a later app launch, offline) sees the file.
      final reopened = LogbookStore(directoryProvider: () async => dir);
      expect(await reopened.count('dev'), 3);
      // Stored oldest-first; the newest-first page starts with the newest.
      final page = await reopened.readPage('dev', offset: 0, limit: 2);
      expect(page.map((e) => e.seconds).toList(), [9, 5]);
      final tail = await reopened.readPage('dev', offset: 2, limit: 50);
      expect(tail.single.seconds, 0);
    });

    test('one JSON file per device, keyed by the sanitized id', () async {
      await store.merge('AA:BB:CC:DD:EE:FF', [rec(0, 0x01)]);
      final files = dir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList();
      expect(files, hasLength(1));
    });

    test('a re-fetch that adds nothing does not grow the stored set', () async {
      await store.merge('dev', [rec(0, 0x01), rec(5, 0x02)]);
      final total = await store.merge('dev', [rec(5, 0x02), rec(0, 0x01)]);
      expect(total, 2);
      expect(await store.count('dev'), 2);
    });
  });
}
