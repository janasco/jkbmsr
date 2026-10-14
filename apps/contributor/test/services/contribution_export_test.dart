import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_contributor/services/contribution_export.dart';

import '../support/jk02_fixtures.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('contributor-export-test');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('the file name is timestamped, id-tagged and .json', () {
    final name = ContributionExport.fileNameFor(
      'c_01926f6a-1c00-7000-8000-000000000001',
      DateTime.utc(2026, 10, 14, 9, 20, 5),
    );
    expect(name, 'jkbmsr-contribution-20261014T092005Z-01926f6a.json');
    // Portable: no colon, which is illegal in a Windows file name.
    expect(name, isNot(contains(':')));
  });

  test('two captures in the same second still get distinct names', () {
    final at = DateTime.utc(2026, 10, 14, 9, 20, 5);
    final a = ContributionExport.fileNameFor('c_aaaaaaaa-....', at);
    final b = ContributionExport.fileNameFor('c_bbbbbbbb-....', at);
    expect(a, isNot(equals(b)));
  });

  test('an id with nothing usable still yields a safe name', () {
    final name = ContributionExport.fileNameFor('c___', DateTime.utc(2026, 1, 2));
    expect(name, 'jkbmsr-contribution-20260102T000000Z-unidentified.json');
  });

  test('write lands the exact UTF-8 bytes of the payload', () async {
    final payload = sampleContribution().encode();
    final exporter = ContributionExporter(documentsDirectory: () async => dir);

    final file = await exporter.write(
      payload,
      contributionId: 'c_01926f6a-1c00-7000-8000-000000000001',
      capturedAt: DateTime.utc(2026, 10, 14, 9, 20),
    );

    expect(file.existsSync(), isTrue);
    expect(await file.readAsBytes(), equals(utf8.encode(payload)));
  });

  test('exportAndShare hands the written file to the share seam', () async {
    final payload = sampleContribution().encode();
    File? shared;
    String? caption;
    final exporter = ContributionExporter(
      documentsDirectory: () async => dir,
      share: (file, text) async {
        shared = file;
        caption = text;
      },
    );

    final returned = await exporter.exportAndShare(
      payload,
      contributionId: 'c_01926f6a-1c00-7000-8000-000000000001',
      capturedAt: DateTime.utc(2026, 10, 14, 9, 20),
    );

    expect(shared, isNotNull);
    expect(shared!.path, returned.path);
    expect(await shared!.readAsString(), payload);
    expect(caption, ContributionExport.shareText);
  });

  test('the export document is self-describing (schemaVersion + full body)',
      () async {
    final exporter = ContributionExporter(documentsDirectory: () async => dir);
    final file = await exporter.write(
      sampleContribution().encode(),
      contributionId: 'c_01926f6a-1c00-7000-8000-000000000001',
      capturedAt: DateTime.utc(2026, 10, 14, 9, 20),
    );

    final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(decoded['schemaVersion'], '1');
    expect(decoded['contributionId'], 'c_01926f6a-1c00-7000-8000-000000000001');
    expect(decoded.keys, contains('bms'));
    expect(decoded.keys, contains('rawFrames'));
  });
}
