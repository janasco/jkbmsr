import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/consent.dart';

/// Persists the single first-run consent decision.
///
/// Why `shared_preferences`: the decision is one small record (a decision and a
/// timestamp), and the app already has no key-value store of its own. `apps/pro`
/// uses `shared_preferences` for exactly this kind of local setting
/// (`lib/app/theme_controller.dart`); `apps/ble` keeps its persistent state in
/// sqflite, which would be far too much machinery for one flag. The choice is
/// recorded in the pubspec and here so it is a decision, not a default.
abstract interface class ConsentStore {
  /// The stored state, or null when the user has not answered yet.
  Future<ConsentState?> read();

  Future<void> write(ConsentState state);

  /// Clears the decision, so the app asks again (used by "revoke consent").
  Future<void> clear();
}

/// The production store, backed by [SharedPreferences].
class SharedPreferencesConsentStore implements ConsentStore {
  static const String _key = 'consent.v1';

  @override
  Future<ConsentState?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return ConsentState.tryFromJson(decoded);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(ConsentState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state.toJson()));
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// A non-persistent store for tests and for a default app instance that never
/// touches a platform plugin.
class InMemoryConsentStore implements ConsentStore {
  ConsentState? _state;

  @override
  Future<ConsentState?> read() async => _state;

  @override
  Future<void> write(ConsentState state) async => _state = state;

  @override
  Future<void> clear() async => _state = null;
}
