import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

/// Runs in a separate background isolate for messages received while the app
/// is backgrounded or terminated. The OS already renders the system
/// notification for a standard FCM notification payload; this only needs to
/// exist so data-only payloads are still delivered to the app.
@pragma('vm:entry-point')
Future<void> jkbmsrFirebaseBackgroundHandler(RemoteMessage message) async {}

/// Centralized manager for push notification configuration and permissions.
/// Backed by real Firebase Cloud Messaging once a Firebase project's
/// google-services.json / GoogleService-Info.plist are added (see
/// docs/AI_HANDOFF_MOBILE_MVP.md); until then, Firebase initialization is
/// caught and preferences still work locally, but no token is registered and
/// no pushes are delivered.
class NotificationService {
  static const String _keyCriticalAlerts = 'jkbmsr_notify_critical';
  static const String _keyTempWarnings = 'jkbmsr_notify_temp';
  static const String _keyOfflineGateways = 'jkbmsr_notify_offline';
  static const String _keyPushToken = 'jkbmsr_push_token';

  // Singleton instance
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final APIClient _apiClient = APIClient();
  bool _firebaseReady = false;
  bool _refreshListenerAttached = false;
  String? _firebaseInitError;
  String? _lastPushError;

  /// Human-readable reason the last push-registration attempt failed, or null
  /// when it last succeeded. Surfaced in Settings so a silent failure (Firebase
  /// not configured, no FCM token issued, backend rejected the token) is
  /// visible instead of looking like "toggling did nothing".
  String? get lastPushError => _firebaseInitError ?? _lastPushError;

  /// Whether Firebase.initializeApp() succeeded — i.e. whether real project
  /// config files are present. Callers (e.g. crash reporting setup in
  /// main.dart) use this to skip Firebase-backed features until then.
  bool get isFirebaseReady => _firebaseReady;

  /// Boots Firebase once at app startup. Safe to call multiple times.
  Future<void> initializeFirebase() async {
    if (_firebaseReady) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(jkbmsrFirebaseBackgroundHandler);
      _firebaseReady = true;
      _firebaseInitError = null;
    } catch (e) {
      debugPrint('JKBMSR: Firebase is not configured yet, push notifications are disabled ($e)');
      _firebaseReady = false;
      _firebaseInitError = 'Firebase is not configured ($e)';
    }
  }

  /// Requests real platform notification authorization. Returns false only
  /// when the platform explicitly denies it; if Firebase isn't configured yet
  /// this still returns true so the local preference toggle remains usable.
  Future<bool> requestPermission() async {
    if (!_firebaseReady) return true;

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Retrieves the real FCM token (or null when Firebase isn't configured),
  /// syncs it and current preferences with JKBMSR Cloud, and attaches a
  /// listener so a rotated token is re-synced automatically.
  Future<String?> getPushToken() async {
    // Retry a failed startup init too: a transient launch failure — or one
    // fixed on the server, like a missing API-key fingerprint — shouldn't need
    // an app restart to recover.
    await initializeFirebase();
    if (!_firebaseReady) {
      _lastPushError = _firebaseInitError ?? 'Firebase did not initialize';
      return null;
    }

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _syncTokenWithBackend(token);
        if (!_refreshListenerAttached) {
          _refreshListenerAttached = true;
          FirebaseMessaging.instance.onTokenRefresh.listen(_syncTokenWithBackend);
        }
        _lastPushError = null;
      } else {
        _lastPushError = 'no FCM token was issued by Google';
      }
      return token;
    } catch (e) {
      debugPrint('JKBMSR: Failed to retrieve FCM token ($e)');
      _lastPushError = 'FCM token request failed ($e)';
      return null;
    }
  }

  /// Upserts the token and current preferences with the backend. Non-fatal
  /// on failure — push registration is best-effort and must never block the
  /// settings screen.
  Future<void> _syncTokenWithBackend(String token) async {
    try {
      await _apiClient.registerPushToken(
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
        criticalAlerts: await isCriticalAlertsEnabled(),
        temperatureAlerts: await isTempWarningsEnabled(),
        offlineAlerts: await isOfflineGatewaysEnabled(),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyPushToken, token);
      _lastPushError = null;
    } catch (e) {
      debugPrint('JKBMSR: Failed to sync push token with backend ($e)');
      _lastPushError = 'server rejected the token ($e)';
    }
  }

  /// Re-syncs the currently registered token's preferences with the backend.
  /// Called after a toggle changes so the server-side prefs match local ones.
  Future<void> _resyncIfRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyPushToken);
    if (token != null) {
      await _syncTokenWithBackend(token);
    }
  }

  /// Removes this installation's push token from JKBMSR Cloud, e.g. on
  /// sign-out, so a stale token stops receiving pushes for this account.
  Future<void> unregister() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyPushToken);
    if (token == null) return;
    try {
      await _apiClient.unregisterPushToken(token);
    } catch (_) {
      // Best-effort: sign-out must proceed even if this fails.
    }
    await prefs.remove(_keyPushToken);
  }

  /// Foreground messages don't produce a system notification on their own;
  /// callers (main.dart) hand these to a UI-level listener (e.g. a toast) via
  /// this stream. Null when Firebase isn't configured yet — accessing
  /// FirebaseMessaging without an initialized app would throw.
  Stream<RemoteMessage>? get onForegroundMessage =>
      _firebaseReady ? FirebaseMessaging.onMessage : null;

  /// Called at launch for a signed-in user: asks for the OS notification
  /// permission and registers the FCM token. The permission used to be
  /// requested only from a Settings toggle, so a user who never touched one
  /// got no notifications at all on Android 13+ — where nothing is ever shown
  /// without POST_NOTIFICATIONS. Both steps are idempotent; the OS remembers a
  /// grant or a denial, so this does not nag.
  Future<void> ensureRegistered() async {
    await requestPermission();
    await getPushToken();
  }

  // --- Preferences Getters ---

  Future<bool> isCriticalAlertsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyCriticalAlerts) ?? true;
  }

  Future<bool> isTempWarningsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyTempWarnings) ?? true;
  }

  Future<bool> isOfflineGatewaysEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOfflineGateways) ?? false;
  }

  // --- Preferences Setters ---

  Future<void> setCriticalAlerts(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCriticalAlerts, enabled);
    await _resyncIfRegistered();
  }

  Future<void> setTempWarnings(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyTempWarnings, enabled);
    await _resyncIfRegistered();
  }

  Future<void> setOfflineGateways(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOfflineGateways, enabled);
    await _resyncIfRegistered();
  }
}
