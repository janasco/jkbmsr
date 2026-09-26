import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

/// Service to persist and manage the user's session JWT token and profile details.
/// Uses SharedPreferences as a cross-platform local storage.
class AuthStore extends ChangeNotifier {
  static const String _keyUserSession = 'jkbmsr_user_session';
  static const String _keyBackgroundedAt = 'jkbmsr_backgrounded_at';

  // How long the app can sit backgrounded/killed before the next foreground
  // requires signing in again — battery telemetry and alert history are
  // sensitive enough to not stay unlocked indefinitely on a lost/borrowed
  // phone. Checked both on app resume and cold start (see main.dart).
  static const Duration idleTimeout = Duration(minutes: 15);

  // Singleton instance
  static final AuthStore instance = AuthStore._internal();
  AuthStore._internal();

  User? _cachedUser;

  /// Loads the persisted session once during app startup. Keeping the value in
  /// memory also lets GoRouter react immediately when a user signs in/out.
  Future<void> load() async {
    _cachedUser = await _readUser();
  }

  /// Persists user credentials locally in preferences.
  Future<void> saveUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(user.toJson());
    await prefs.setString(_keyUserSession, jsonStr);
    _cachedUser = user;
    notifyListeners();
  }

  /// Restores user session details from local storage.
  Future<User?> getUser() async {
    if (_cachedUser != null) return _cachedUser;
    return _readUser();
  }

  Future<User?> _readUser() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyUserSession);
    if (jsonStr == null) return null;

    try {
      final decodedMap = jsonDecode(jsonStr) as Map<String, dynamic>;
      final user = User.fromJson(decodedMap);
      _cachedUser = user;
      return user;
    } catch (_) {
      // Clear corrupt session
      await clearUser();
      return null;
    }
  }

  /// Returns the current active session JWT.
  Future<String?> getToken() async {
    final user = await getUser();
    return user?.token;
  }

  /// Checks if a valid session JWT exists.
  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Clears user credentials to perform sign out.
  Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserSession);
    await prefs.remove(_keyBackgroundedAt);
    _cachedUser = null;
    notifyListeners();
  }

  /// Marks "now" as the moment the app left the foreground. Persisted (not
  /// just in memory) so the check below also catches the app being killed
  /// entirely while backgrounded, not just app-switcher backgrounding.
  Future<void> recordBackgrounded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyBackgroundedAt, DateTime.now().millisecondsSinceEpoch);
  }

  /// Call on every foreground transition (app resume, and once at cold
  /// start after [load]). Signs the user out — via the same [clearUser]
  /// path GoRouter already watches to bounce to /login — if the app sat
  /// backgrounded for longer than [idleTimeout]. Returns true if it did.
  Future<bool> enforceIdleTimeout() async {
    final prefs = await SharedPreferences.getInstance();
    final backgroundedAt = prefs.getInt(_keyBackgroundedAt);
    if (backgroundedAt == null) return false;

    final elapsed = DateTime.now().millisecondsSinceEpoch - backgroundedAt;
    if (elapsed >= idleTimeout.inMilliseconds) {
      await clearUser();
      return true;
    }

    await prefs.remove(_keyBackgroundedAt);
    return false;
  }
}
