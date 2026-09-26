import 'package:flutter/services.dart';

/// Centralized haptic feedback utilities for the JKBMSR mobile app.
/// Wraps Flutter's HapticFeedback with semantic method names so callers
/// don't need to think about which platform primitive to use.
class JKBMSRHaptics {
  JKBMSRHaptics._();

  /// Light tap — used for button presses, tab switches, segmented control taps.
  static Future<void> lightImpact() async {
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {
      // Web and some emulators don't support haptics; silently ignore.
    }
  }

  /// Medium tap — used for pull-to-refresh trigger, swipe actions, toggles.
  static Future<void> mediumImpact() async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// Heavy tap — used for destructive actions (delete, revoke, sign out).
  static Future<void> heavyImpact() async {
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Success — used after a successful save, claim, or completion.
  static Future<void> success() async {
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// Error — used when an operation fails or an error toast appears.
  static Future<void> error() async {
    try {
      await HapticFeedback.vibrate();
    } catch (_) {}
  }
}
