import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to cache dynamic REST API JSON payloads locally.
/// Enables seamless offline fallbacks and rapid initial page loads.
class CacheService {
  // Singleton instance
  static final CacheService instance = CacheService._internal();
  CacheService._internal();

  /// Saves a JSON map payload associated with a key to local preferences,
  /// alongside the time it was cached so callers can show cache age when a
  /// live fetch later fails and this fallback is served instead.
  Future<void> cacheData(String key, dynamic data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wrapper = {'cachedAt': DateTime.now().toIso8601String(), 'data': data};
      await prefs.setString('cache_$key', jsonEncode(wrapper));
    } catch (_) {
      // Caching is non-critical, fail silently in production
    }
  }

  /// Restores cached JSON payload by key.
  Future<dynamic> getCachedData(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('cache_$key');
      if (jsonStr == null) return null;
      final decoded = jsonDecode(jsonStr);
      // Older cache entries (pre-timestamp) were stored unwrapped; fall back
      // to returning them as-is so an app update doesn't lose the cache.
      if (decoded is Map && decoded.containsKey('data') && decoded.containsKey('cachedAt')) {
        return decoded['data'];
      }
      return decoded;
    } catch (_) {
      return null;
    }
  }

  /// Returns when the cached payload for `key` was stored, or null if
  /// there's no cached entry or it predates timestamp tracking.
  Future<DateTime?> getCachedAt(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('cache_$key');
      if (jsonStr == null) return null;
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map && decoded['cachedAt'] is String) {
        return DateTime.tryParse(decoded['cachedAt'] as String);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Clears all local cached data.
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('cache_')).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
