import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// The on-device export of a contribution (plan §3.5, the mandatory offline
/// fallback).
///
/// A contribution must never be lost because the network was down, so the same
/// bytes that [ContributionUploader.submit] would POST can be written to a
/// self-describing `.json` file and handed to the OS share sheet. The file
/// carries the full versioned payload (`schemaVersion` included), so it can be
/// emailed or uploaded later without any app involvement.
///
/// Pure formatting and file I/O live here; the sharing call is a seam so a test
/// can exercise the byte-for-byte write without a platform plugin.
abstract final class ContributionExport {
  /// The share-sheet caption shown beside the file. User-facing prose names the
  /// product "JK BMS Contributor", never "JKBMSR".
  static const String shareText = 'JK BMS Contributor — anonymous capture';

  /// `jkbmsr-contribution-<utc>-<shortid>.json`.
  ///
  /// The timestamp is basic ISO-8601 with the colons removed (`20261014T092000Z`)
  /// because a colon is not portable in a file name. The short id is the first
  /// eight characters of the contribution's own random id, so two captures made
  /// in the same second still produce distinct files.
  static String fileNameFor(String contributionId, DateTime capturedAt) {
    final t = capturedAt.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${t.year}${two(t.month)}${two(t.day)}'
        'T${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
    return 'jkbmsr-contribution-$stamp-${_shortId(contributionId)}.json';
  }

  /// The identifying fragment of `c_<uuid7>`, with anything that is not
  /// filename-safe removed. Never empty.
  static String _shortId(String contributionId) {
    final cleaned = contributionId
        .replaceFirst(RegExp(r'^c_'), '')
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (cleaned.isEmpty) return 'unidentified';
    return cleaned.length <= 8 ? cleaned : cleaned.substring(0, 8);
  }
}

/// Writes a contribution to a file and (optionally) shares it. The platform
/// bits are injectable so the write path is unit-testable.
class ContributionExporter {
  ContributionExporter({
    Future<Directory> Function()? documentsDirectory,
    Future<void> Function(File file, String text)? share,
  })  : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory,
        _share = share ?? _shareFile;

  final Future<Directory> Function() _documentsDirectory;
  final Future<void> Function(File file, String text) _share;

  /// Writes [payload] to the app documents directory and returns the file.
  ///
  /// The bytes written are exactly `utf8.encode(payload)` — the same bytes the
  /// uploader would put on the wire — because `File.writeAsString` defaults to
  /// UTF-8 and the string is the single source for both paths.
  Future<File> write(
    String payload, {
    required String contributionId,
    DateTime? capturedAt,
  }) async {
    final at = (capturedAt ?? DateTime.now()).toUtc();
    final dir = await _documentsDirectory();
    final file = File(
      '${dir.path}/${ContributionExport.fileNameFor(contributionId, at)}',
    );
    await file.writeAsString(payload, flush: true);
    return file;
  }

  /// Writes the file and opens the OS share sheet. Returns the written file so
  /// a caller can report the path if sharing is unavailable.
  Future<File> exportAndShare(
    String payload, {
    required String contributionId,
    DateTime? capturedAt,
  }) async {
    final file = await write(
      payload,
      contributionId: contributionId,
      capturedAt: capturedAt,
    );
    await _share(file, ContributionExport.shareText);
    return file;
  }

  static Future<void> _shareFile(File file, String text) =>
      Share.shareXFiles([XFile(file.path)], text: text);
}
