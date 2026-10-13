import 'package:flutter/material.dart';

/// Compile-time facts about the app.
///
/// There is deliberately no product logic here yet. This exists so the app's
/// name, one-line description and accent colour are declared once and reused,
/// rather than retyped (and drifting) across widgets.
abstract final class AppInfo {
  /// User-facing app name.
  static const String appName = 'JK BMS Contributor';

  /// One-line description shown on the home screen.
  static const String tagline =
      'Help improve JK-BMS support by contributing your device data.';

  /// Accent colour shared with the other JKBMSR apps (emerald green).
  static const Color brandColor = Color(0xFF10B981);
}
