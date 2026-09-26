import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide theme mode: follows the system by default, with a persisted
/// in-app override (System / Light / Dark) — mirroring the web dashboard's
/// behavior.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController._(super.initialMode);

  static const _prefsKey = 'jkbmsr.themeMode';

  static Future<ThemeController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    final mode = ThemeMode.values.firstWhere(
      (candidate) => candidate.name == stored,
      orElse: () => ThemeMode.system,
    );
    return ThemeController._(mode);
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == value) {
      return;
    }
    value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }
}
