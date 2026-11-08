import 'package:flutter/material.dart';

/// Compile-time facts about the app.
///
/// There is deliberately no product logic here yet. This exists so the app's
/// name, one-line description and accent colour are declared once and reused,
/// rather than retyped (and drifting) across widgets.
abstract final class AppInfo {
  /// User-facing app name.
  static const String appName = 'JK BMS Contributor';

  /// Build version, carried in a contribution's `app.version`.
  ///
  /// Kept in step with pubspec's `version:` **by hand**, and that is exactly how
  /// it drifted: it read `1.0.1+2` from the 1.0.1 release through 1.0.2, 1.0.3
  /// and 1.0.4, so every contribution in that period reported a version the app
  /// was not, and "which build did this come from" was unanswerable from the
  /// data. `test/services/app_version_test.dart` now fails if the two disagree,
  /// which is cheaper than a plugin and catches the mistake where it is made.
  static const String version = '1.0.5+6';

  /// One-line description shown on the home screen.
  static const String tagline =
      'Help improve JK-BMS support by contributing your device data.';

  /// Accent colour shared with the other JKBMSR apps (emerald green).
  static const Color brandColor = Color(0xFF10B981);
}
