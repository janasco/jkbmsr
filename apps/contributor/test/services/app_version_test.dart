import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_contributor/services/app_info.dart';

/// `AppInfo.version` is hand-kept and rides in every contribution's
/// `app.version`, so a drift between it and `pubspec.yaml` is not cosmetic —
/// it makes "which build produced this capture" unanswerable from the data.
///
/// It drifted exactly that way: it read `1.0.1+2` from the 1.0.1 release through
/// 1.0.2, 1.0.3 and 1.0.4. Reading the real version at runtime would mean adding
/// a package for one string, so the guard is a test that fails where the mistake
/// is made.
void main() {
  test('AppInfo.version is the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:[ \t]*(\S+)', multiLine: true).firstMatch(pubspec);

    expect(match, isNotNull, reason: 'pubspec.yaml has no version: line');
    expect(
      AppInfo.version,
      match!.group(1),
      reason: 'bump both together — the app reports one and Play ships the other',
    );
  });
}
