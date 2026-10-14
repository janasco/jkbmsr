// Writes the app's OWN wire payload to a file, so the contribution ingest can be
// exercised with a document the app actually produces rather than a
// hand-written guess at the schema.
//
//     flutter test tool/dump_contribution_payload.dart
//     OUT=/tmp/opencode/contribution.json flutter test tool/dump_contribution_payload.dart
//
// `sampleContribution()` is built from the real JK-B2A24S capture already used
// by the tests, so the document is real decoded data, not invented values.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../test/support/jk02_fixtures.dart';

void main() {
  test('writes the real contribution payload', () {
    final contribution = sampleContribution();
    final payload = contribution.encode();
    final out = Platform.environment['OUT'] ?? 'build/contribution-payload.json';
    File(out).writeAsStringSync(payload);
    // The app's own cap, checked the same way the uploader checks it.
    print('wrote $out  chars=${payload.length}  bytes=${contribution.encodedBytes()}  '
        'withinCap=${contribution.isWithinSizeCap()}');
  });
}
