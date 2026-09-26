import 'package:flutter/material.dart';
import 'app_database.dart';

class ThemeService {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  final _db = AppDatabase();

  // Follows the OS theme until the user explicitly picks one in Settings.
  final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

  static const String _prefKey = 'jkbmsr_theme_mode';

  Future<void> init() async {
    final savedMode = await _db.getValue(_prefKey);
    if (savedMode == 'light') {
      themeModeNotifier.value = ThemeMode.light;
    } else if (savedMode == 'dark') {
      themeModeNotifier.value = ThemeMode.dark;
    } else {
      themeModeNotifier.value = ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    String modeStr = 'system';
    if (mode == ThemeMode.light) {
      modeStr = 'light';
    } else if (mode == ThemeMode.dark) {
      modeStr = 'dark';
    }
    await _db.setValue(_prefKey, modeStr);
  }

  String get currentThemeString {
    switch (themeModeNotifier.value) {
      case ThemeMode.system:
        return 'SYSTEM';
      case ThemeMode.light:
        return 'LIGHT';
      case ThemeMode.dark:
        return 'DARK';
    }
  }
}

class AppColors {
  static bool isDark(BuildContext context) {
    final theme = Theme.of(context).brightness;
    return theme == Brightness.dark;
  }

  static Color bgCanvas(BuildContext context) =>
      isDark(context) ? const Color(0xFF090D10) : const Color(0xFFF8FAFC);

  static Color bgCard(BuildContext context) =>
      isDark(context) ? const Color(0xFF131A20) : const Color(0xFFFFFFFF);

  static Color bgNested(BuildContext context) =>
      isDark(context) ? const Color(0xFF090D10) : const Color(0xFFF1F5F9);

  static Color borderColor(BuildContext context) =>
      isDark(context) ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0);

  static Color textPrimary(BuildContext context) =>
      isDark(context) ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

  static Color textSecondary(BuildContext context) =>
      const Color(0xFF64748B);

  static Color textMuted(BuildContext context) =>
      isDark(context) ? const Color(0xFF94A3B8) : const Color(0xFF475569);

  static Color inputFill(BuildContext context) =>
      isDark(context) ? const Color(0xFF1E2830) : const Color(0xFFF1F5F9);

  static const Color accentGreen = Color(0xFF10B981);
  static const Color accentBlue = Color(0xFF38BDF8);
  static const Color accentAmber = Color(0xFFF59E0B);
  static const Color accentRed = Color(0xFFEF4444);
}
