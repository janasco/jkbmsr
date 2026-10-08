import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_store.dart';
import 'request_deduplication.dart';
import '../models/user.dart';
import '../models/device.dart';
import '../models/device_share.dart';
import '../models/device_wifi.dart';
import '../models/telemetry.dart';
import '../models/alert.dart';
import '../models/ota_event.dart';
import '../models/firmware_release.dart';
import '../models/ble_history_event.dart';
import '../models/recent_session.dart';
import '../models/cloud_history_point.dart';
import '../models/telemetry_history_point.dart';
import 'cache_service.dart';
import 'session_expiry_handler.dart';

/// Thrown by login when the account exists but hasn't verified its email
/// yet (registration no longer issues a token until that happens — see
/// jkbmsr-api's POST /user/login). Carries the email so the UI can drop
/// straight into the OTP-verify screen instead of just showing an error.
class EmailVerificationRequiredException implements Exception {
  final String email;
  final String message;
  EmailVerificationRequiredException(this.email, this.message);
  @override
  String toString() => message;
}

/// Thrown when the server rejects an already-signed-in request because the
/// token is dead (expired or revoked) — see SessionExpiryHandler, which
/// _handleResponse already triggers before this is ever thrown. Callers
/// generally don't need to catch this specifically: the sign-out + redirect
/// to /login has already happened by the time it propagates.
class SessionExpiredException implements Exception {
  final String message;
  SessionExpiredException(this.message);
  @override
  String toString() => message;
}

/// Thrown on a 402 with `subscriptionStatus: "inactive"` — the device's
/// Cloud Service subscription lapsed (see jkbmsr-api's dashboard.ts). Kept
/// distinguishable from a generic Exception so screens can render an
/// upsell instead of a plain error, and so cache-fallback catch blocks
/// (getTelemetryHistory below) can rethrow it instead of silently masking
/// an access problem as "just show whatever's cached".
class CloudServiceRequiredException implements Exception {
  final String message;
  CloudServiceRequiredException(this.message);
  @override
  String toString() => message;
}

/// Centralized API client for communicating with the JKBMSR Cloud REST API.
/// Coordinates request headers, auth token inclusion, and JSON conversions.
///
/// This is a singleton: every screen shares one instance, which means one
/// shared underlying http.Client — connection pooling (HTTP keep-alive)
/// instead of 13 separate clients each opening their own sockets — and a
/// single place for request deduplication to actually be effective.
class APIClient with RequestDeduplicationMixin {
  static const String _defaultBaseUrl = 'https://api.jkbmsr.com';

  // Singleton instance. Tests can inject their own via [configure].
  static final APIClient instance = APIClient._internal(
    baseUrl: _defaultBaseUrl,
  );

  // Kept for backwards compatibility with existing call sites
  // (`APIClient()` still works and returns the shared instance).
  factory APIClient({String? baseUrl, http.Client? client}) {
    if (baseUrl != null || client != null) {
      // Custom configuration is only allowed once, before first use.
      configure(baseUrl: baseUrl, client: client);
    }
    return instance;
  }

  APIClient._internal({
    required this.baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Reconfigures the shared instance (e.g. pointing at a staging API or
  /// injecting a mock client in tests). Only effective before the first
  /// network call; later calls are ignored.
  static void configure({String? baseUrl, http.Client? client}) {
    if (baseUrl != null && instance.baseUrl != baseUrl) {
      instance.baseUrl = baseUrl;
    }
    if (client != null) {
      instance._client.close();
      instance._client = client;
    }
  }

  String baseUrl;
  http.Client _client;

  /// Helper to compile global JSON headers including Bearer authorization tokens.
  Future<Map<String, String>> _headers() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final token = await AuthStore.instance.getToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Handles parsing API responses, checking status codes and formatting errors.
  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }

    Map<String, dynamic>? decoded;
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is Map<String, dynamic>) decoded = parsed;
    } catch (_) {}

    final errorMessage = (decoded?['error'] as String?) ?? 'API Call Failed';
    final verifyEmail = decoded?['email'];
    if (decoded?['emailVerificationRequired'] == true && verifyEmail is String) {
      throw EmailVerificationRequiredException(verifyEmail, errorMessage);
    }
    // "Unauthorized" at 401 is the exact, reserved response shape userAuth/
    // accountAuth use for a missing/expired/invalid token (see jkbmsr-api's
    // middleware/auth.ts) — every other 401 in the API (wrong password, bad
    // OTP, wrong current-password) uses a different message, so this check
    // can't misfire on a plain failed login attempt.
    if (response.statusCode == 401 && errorMessage == 'Unauthorized') {
      unawaited(SessionExpiryHandler.handle());
      throw SessionExpiredException(errorMessage);
    }
    if (response.statusCode == 402 && decoded?['subscriptionStatus'] == 'inactive') {
      throw CloudServiceRequiredException(errorMessage);
    }
    throw Exception(errorMessage);
  }

  // --- Auth Endpoints ---

  /// Performs user sign in against JKBMSR Cloud.
  /// When Biometric Unlock is enabled, also saves the credentials to the OS
  /// keychain so a later session expiry can re-login silently after an
  /// biometric check (see BiometricRelogin).
  Future<User> login(String email, String password) async {
    final url = Uri.parse('$baseUrl/api/v1/user/login');
    final response = await _client.post(
      url,
      headers: await _headers(),
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = _handleResponse(response);
    final user = User.fromJson(data);
    await AuthStore.instance.saveUser(user);
    return user;
  }

  /// Sends (or resends) an emailed OTP code — used both for the account's
  /// own "sign in with a code" flow and for completing registration
  /// verification, since the backend serves both from the same endpoint.
  Future<void> requestOtpCode(String email) async {
    final url = Uri.parse('$baseUrl/api/v1/user/otp/request');
    final response = await _client.post(
      url,
      headers: await _headers(),
      body: jsonEncode({'email': email}),
    );
    _handleResponse(response);
  }

  /// Verifies an emailed OTP code and returns the resulting session —
  /// completes registration verification when called right after an
  /// EmailVerificationRequiredException, or signs in directly otherwise.
  Future<User> verifyOtpCode(String email, String code) async {
    final url = Uri.parse('$baseUrl/api/v1/user/otp/verify');
    final response = await _client.post(
      url,
      headers: await _headers(),
      body: jsonEncode({'email': email, 'code': code}),
    );
    final data = _handleResponse(response);
    final user = User.fromJson(data);
    await AuthStore.instance.saveUser(user);
    return user;
  }

  /// Exchanges a native Google Sign-In ID token (see GoogleAuthService) for a
  /// JKBMSR session, via the same backend endpoint the website's Google
  /// button uses.
  Future<User> loginWithGoogle(String idToken) async {
    final url = Uri.parse('$baseUrl/api/v1/user/google');
    final response = await _client.post(
      url,
      headers: await _headers(),
      body: jsonEncode({'credential': idToken}),
    );
    final data = _handleResponse(response);
    final user = User.fromJson(data);
    await AuthStore.instance.saveUser(user);
    return user;
  }

  /// Exchanges a stored biometric unlock token for a fresh session.
  Future<User> biometricLogin(String unlockToken) async {
    final url = Uri.parse('$baseUrl/api/v1/user/biometric/login');
    final response = await _client.post(
      url,
      headers: await _headers(),
      body: jsonEncode({'unlockToken': unlockToken}),
    );
    final data = _handleResponse(response);
    final user = User.fromJson(data);
    await AuthStore.instance.saveUser(user);
    return user;
  }

  /// Requests an emailed verification code, for enabling biometric unlock
  /// without entering the account password.
  Future<void> requestBiometricOtp() async {
    final url = Uri.parse('$baseUrl/api/v1/user/biometric/otp/request');
    final response = await _client.post(url, headers: await _headers());
    _handleResponse(response);
  }

  /// Enables biometric unlock, verified by the account password OR an emailed
  /// code. Returns the long-lived unlock token to store in the keystore.
  Future<String> enableBiometric({String? password, String? otp}) async {
    final url = Uri.parse('$baseUrl/api/v1/user/biometric/enable');
    final response = await _client.post(
      url,
      headers: await _headers(),
      body: jsonEncode({
        if (password != null) 'password': password,
        if (otp != null) 'otp': otp,
      }),
    );
    final data = _handleResponse(response);
    return data['unlockToken'] as String? ?? '';
  }

  /// Revokes this account's biometric unlock tokens server-side.
  Future<void> disableBiometric() async {
    final url = Uri.parse('$baseUrl/api/v1/user/biometric/disable');
    final response = await _client.post(url, headers: await _headers());
    _handleResponse(response);
  }

  /// Performs user registration.
  Future<User> register(String email, String password) async {
    final url = Uri.parse('$baseUrl/api/v1/user/register');
    final response = await _client.post(
      url,
      headers: await _headers(),
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = _handleResponse(response);
    final user = User.fromJson(data);
    await AuthStore.instance.saveUser(user);
    return user;
  }

  /// How the current session authenticated — 'password' | 'otp' | 'google' |
  /// 'demo'. Used to decide whether the delete-account confirmation needs a
  /// password field: jkbmsr-api's DELETE /user/me only requires one for a
  /// password-authenticated session (an OTP or Google session already proved
  /// live ownership of the account out-of-band).
  Future<String> getAuthMethod() async {
    final url = Uri.parse('$baseUrl/api/v1/user/me');
    final response = await _client.get(url, headers: await _headers());
    final data = _handleResponse(response) as Map<String, dynamic>;
    return (data['user']?['authMethod'] as String?) ?? 'password';
  }

  /// Permanently deletes the signed-in account (see jkbmsr-api's DELETE
  /// /user/me): every gateway it owns and that gateway's telemetry/alert/OTA
  /// history, device shares in either direction,
  /// push tokens, and the account itself. [currentPassword] is required only
  /// for a password-authenticated session; pass null otherwise.
  Future<int> deleteAccount({required String confirmEmail, String? currentPassword}) async {
    final url = Uri.parse('$baseUrl/api/v1/user/me');
    final response = await _client.delete(
      url,
      headers: await _headers(),
      body: jsonEncode({
        'confirmEmail': confirmEmail,
        if (currentPassword != null) 'currentPassword': currentPassword,
      }),
    );
    final data = _handleResponse(response) as Map<String, dynamic>;
    return data['devicesDeleted'] as int? ?? 0;
  }

  // --- Dashboard Device Endpoints ---

  /// Fetches a list of devices registered under user access. Caches the
  /// response (with a timestamp — see CacheService) so a failed live fetch
  /// can fall back to the last-known list; callers can check
  /// `CacheService.instance.getCachedAt('device_list')` to show data age.
  Future<List<Device>> getDevices() {
    return deduplicate('device_list', () async {
      const cacheKey = 'device_list';
      try {
        final url = Uri.parse('$baseUrl/api/v1/dashboard/devices');
        final response = await _client.get(url, headers: await _headers());
        final data = _handleResponse(response);
        await CacheService.instance.cacheData(cacheKey, data);
        final list = data['devices'] as List<dynamic>? ?? [];
        return list.map((item) => Device.fromJson(item as Map<String, dynamic>)).toList();
      } catch (e) {
        final cached = await CacheService.instance.getCachedData(cacheKey);
        if (cached != null) {
          final list = cached['devices'] as List<dynamic>? ?? [];
          return list.map((item) => Device.fromJson(item as Map<String, dynamic>)).toList();
        }
        rethrow;
      }
    });
  }

  /// Claims an unowned (or already-owned-by-this-account) device using its
  /// claim code — the preferred proof-of-possession — or, only as a legacy
  /// fallback, its raw device secret. Throws with the server's error message
  /// on invalid codes, unverified email, or a device claimed by another account.
  Future<void> claimDevice(String deviceId, {String? claimCode, String? deviceSecret}) async {
    final url = Uri.parse('$baseUrl/api/v1/user/devices/claim');
    final body = <String, dynamic>{'deviceId': deviceId};
    if (claimCode != null && claimCode.isNotEmpty) body['claimCode'] = claimCode;
    if (deviceSecret != null && deviceSecret.isNotEmpty) body['deviceSecret'] = deviceSecret;
    final response = await _client.post(
      url,
      headers: await _headers(),
      body: jsonEncode(body),
    );
    _handleResponse(response);
  }

  /// Updates the user-facing name of a device owned by the signed-in account.
  Future<String> updateDeviceName(String deviceId, String name) async {
    final url = Uri.parse('$baseUrl/api/v1/dashboard/devices/$deviceId');
    final response = await _client.put(
      url,
      headers: await _headers(),
      body: jsonEncode({'name': name}),
    );
    final data = _handleResponse(response) as Map<String, dynamic>;
    final device = data['device'] as Map<String, dynamic>;
    return device['name'] as String;
  }

  /// Fetches details of a device including real-time Telemetry metrics.
  Future<Map<String, dynamic>> getDeviceDetails(String deviceId) {
    return deduplicate('device_detail_$deviceId', () async {
      final cacheKey = 'device_detail_$deviceId';
      try {
        final url = Uri.parse('$baseUrl/api/v1/dashboard/devices/$deviceId');
        final response = await _client.get(url, headers: await _headers());
        final data = _handleResponse(response);
        await CacheService.instance.cacheData(cacheKey, data);
        return {
          'device': Device.fromJson(data['device'] as Map<String, dynamic>),
          'telemetry': Telemetry.fromJson(data['telemetry'] as Map<String, dynamic>),
        };
      } catch (e) {
        final cached = await CacheService.instance.getCachedData(cacheKey);
        if (cached != null) {
          return {
            'device': Device.fromJson(cached['device'] as Map<String, dynamic>),
            'telemetry': Telemetry.fromJson(cached['telemetry'] as Map<String, dynamic>),
          };
        }
        rethrow;
      }
    });
  }

  /// Short-term voltage/current trend for the Gauge & Sparkline / Icon Tiles
  /// dashboard templates — free and ungated, unlike the Cloud Service
  /// history below (`getTelemetryHistory`, which requires an active
  /// subscription). Deliberately not routed through that method.
  ///
  /// [hours] controls how far back the trend reaches — the dashboard's
  /// time-range selector maps 1h/24h/7d onto this.
  Future<List<TelemetryHistoryPoint>> getRecentTelemetryHistory(
    String deviceId, {
    int hours = 6,
    int limit = 60,
  }) {
    return deduplicate('telemetry_recent_history_${deviceId}_$hours', () async {
      final cacheKey = 'telemetry_recent_history_$deviceId';
      try {
        final url = Uri.parse('$baseUrl/api/v1/dashboard/devices/$deviceId/telemetry/history')
            .replace(queryParameters: {'hours': '$hours', 'limit': '$limit'});
        final response = await _client.get(url, headers: await _headers());
        final data = _handleResponse(response) as Map<String, dynamic>;
        await CacheService.instance.cacheData(cacheKey, data);
        final points = data['points'] as List<dynamic>? ?? [];
        return points.map((item) => TelemetryHistoryPoint.fromJson(item as Map<String, dynamic>)).toList();
      } catch (e) {
        final cached = await CacheService.instance.getCachedData(cacheKey);
        if (cached != null) {
          final points = cached['points'] as List<dynamic>? ?? [];
          return points.map((item) => TelemetryHistoryPoint.fromJson(item as Map<String, dynamic>)).toList();
        }
        return [];
      }
    });
  }

  // --- Telemetry History (Cloud Service) ---

  ({bool available, bool downsampled, List<CloudHistoryPoint> points}) _parseTelemetryHistory(Map<String, dynamic> data) {
    final available = data['available'] as bool? ?? false;
    if (!available) {
      return (available: false, downsampled: false, points: <CloudHistoryPoint>[]);
    }
    final rows = (data['rows'] as List<dynamic>? ?? [])
        .map((item) => CloudHistoryPoint.fromJson(item as Map<String, dynamic>))
        .toList();
    return (available: true, downsampled: data['downsampled'] as bool? ?? false, points: rows);
  }

  /// Cloud Service long-term history (up to 365 days) — what makes the new
  /// history screen work offline: a live fetch caches its raw response, and
  /// any later failure serves that cache back instead of an error (`fromCache`
  /// / `cachedAt` let the screen show a "showing cached data from X ago"
  /// notice rather than pretending it's live). The one exception is
  /// [CloudServiceRequiredException]: that's an access state, not a
  /// connectivity failure, so it's rethrown rather than papered over with
  /// stale cached data the account may no longer be entitled to see.
  Future<({bool available, bool downsampled, List<CloudHistoryPoint> points, bool fromCache, DateTime? cachedAt})> getTelemetryHistory(
    String deviceId, {
    required String from,
    required String to,
  }) {
    return deduplicate('telemetry_history_${deviceId}_$from-$to', () async {
      final cacheKey = 'telemetry_history_${deviceId}_${from}_$to';
      try {
        final url = Uri.parse('$baseUrl/api/v1/dashboard/devices/$deviceId/telemetry/monthly-history')
            .replace(queryParameters: {'from': from, 'to': to});
        final response = await _client.get(url, headers: await _headers());
        final data = _handleResponse(response) as Map<String, dynamic>;
        await CacheService.instance.cacheData(cacheKey, data);
        final parsed = _parseTelemetryHistory(data);
        return (available: parsed.available, downsampled: parsed.downsampled, points: parsed.points, fromCache: false, cachedAt: null);
      } on CloudServiceRequiredException {
        rethrow;
      } catch (e) {
        final cached = await CacheService.instance.getCachedData(cacheKey);
        if (cached != null) {
          final parsed = _parseTelemetryHistory(cached as Map<String, dynamic>);
          final cachedAt = await CacheService.instance.getCachedAt(cacheKey);
          return (available: parsed.available, downsampled: parsed.downsampled, points: parsed.points, fromCache: true, cachedAt: cachedAt);
        }
        rethrow;
      }
    });
  }

  /// Full-resolution CSV backup — a point-in-time export, so unlike the
  /// method above there's no cache fallback: it either succeeds live or the
  /// caller is told to try again.
  Future<({List<int> bytes, String filename})> downloadTelemetryExportBytes(
    String deviceId, {
    required String from,
    required String to,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/dashboard/devices/$deviceId/telemetry/export')
        .replace(queryParameters: {'from': from, 'to': to});
    final response = await _client.get(url, headers: await _headers());
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _handleResponse(response);
    }
    final disposition = response.headers['content-disposition'] ?? '';
    final filename = RegExp(r'filename="([^"]+)"').firstMatch(disposition)?.group(1) ?? '$deviceId-telemetry.csv';
    return (bytes: response.bodyBytes, filename: filename);
  }

  // --- Alerts ---

  /// Fetches alerts. `status` is `active` (default, unresolved only),
  /// `resolved`, or `all`. Returns the page of alerts alongside whether more
  /// pages exist at `offset + limit`.
  Future<({List<Alert> alerts, bool hasMore})> getAlerts({
    String status = 'active',
    int limit = 50,
    int offset = 0,
  }) {
    return deduplicate('alerts_${status}_$offset', () async {
      final cacheKey = 'alerts_${status}_${offset ~/ (limit == 0 ? 1 : limit)}';
      try {
        final url = Uri.parse('$baseUrl/api/v1/dashboard/alerts').replace(queryParameters: {
          'status': status,
          'limit': '$limit',
          'offset': '$offset',
        });
        final response = await _client.get(url, headers: await _headers());
        final data = _handleResponse(response);
        await CacheService.instance.cacheData(cacheKey, data);
        final list = data['alerts'] as List<dynamic>? ?? [];
        return (
          alerts: list.map((item) => Alert.fromJson(item as Map<String, dynamic>)).toList(),
          hasMore: data['hasMore'] as bool? ?? false,
        );
      } catch (e) {
        final cached = await CacheService.instance.getCachedData(cacheKey);
        if (cached != null) {
          final list = cached['alerts'] as List<dynamic>? ?? [];
          return (
            alerts: list.map((item) => Alert.fromJson(item as Map<String, dynamic>)).toList(),
            hasMore: cached['hasMore'] as bool? ?? false,
          );
        }
        rethrow;
      }
    });
  }

  /// Manually resolves an alert before its underlying condition clears
  /// (e.g. silencing a low-priority warning you've already dealt with).
  /// Returns the alert's `resolvedAt` timestamp as reported by the server.
  /// Throws with the server's message if the alert doesn't exist or belongs
  /// to a gateway this account can't access (404 / 403).
  Future<String> resolveAlert(String alertId) async {
    final url = Uri.parse('$baseUrl/api/v1/dashboard/alerts/$alertId/resolve');
    final response = await _client.post(url, headers: await _headers());
    final data = _handleResponse(response) as Map<String, dynamic>;
    return data['resolvedAt'] as String? ?? '';
  }

  /// Bulk-acknowledge every open alert (optionally scoped to one gateway).
  /// Returns how many were resolved.
  Future<int> resolveAllAlerts({String? deviceId}) async {
    final query = deviceId != null
        ? '?deviceId=${Uri.encodeQueryComponent(deviceId)}'
        : '';
    final url =
        Uri.parse('$baseUrl/api/v1/dashboard/alerts/resolve-all$query');
    final response = await _client.post(url, headers: await _headers());
    final data = _handleResponse(response) as Map<String, dynamic>;
    return data['resolvedCount'] as int? ?? 0;
  }

  /// Permanently deletes a single alert from the account's history. Unlike
  /// [resolveAlert], this cannot be undone. Returns the deleted alert id as
  /// reported by the server (falls back to the id passed in).
  Future<String> deleteAlert(String alertId) async {
    final url = Uri.parse('$baseUrl/api/v1/dashboard/alerts/$alertId');
    final response = await _client.delete(url, headers: await _headers());
    final data = _handleResponse(response) as Map<String, dynamic>;
    return data['deleted'] as String? ?? alertId;
  }

  /// Permanently deletes the account's resolved-alert history, optionally
  /// scoped to one gateway. Unlike [resolveAllAlerts] (which only marks active
  /// alarms resolved), this is irreversible. Returns how many rows were
  /// deleted.
  Future<int> deleteResolvedAlerts({String? deviceId}) async {
    final query = deviceId != null
        ? '?deviceId=${Uri.encodeQueryComponent(deviceId)}'
        : '';
    final url = Uri.parse('$baseUrl/api/v1/dashboard/alerts/resolved$query');
    final response = await _client.delete(url, headers: await _headers());
    final data = _handleResponse(response) as Map<String, dynamic>;
    return data['deletedCount'] as int? ?? 0;
  }

  // --- Device Configuration ---

  /// Fetches configurations and settings parameters for a specific gateway.
  Future<Map<String, dynamic>> getDeviceConfig(String deviceId) {
    return deduplicate('device_config_$deviceId', () async {
      final cacheKey = 'device_config_$deviceId';
      try {
        final url = Uri.parse('$baseUrl/api/v1/dashboard/devices/$deviceId/config');
        final response = await _client.get(url, headers: await _headers());
        final data = _handleResponse(response);
        await CacheService.instance.cacheData(cacheKey, data);
        return data['config'] as Map<String, dynamic>? ?? {};
      } catch (e) {
        final cached = await CacheService.instance.getCachedData(cacheKey);
        if (cached != null) {
          return cached['config'] as Map<String, dynamic>? ?? {};
        }
        rethrow;
      }
    });
  }

  /// Updates settings configurations for a specific gateway.
  Future<bool> updateDeviceConfig(String deviceId, Map<String, dynamic> configBody) async {
    final url = Uri.parse('$baseUrl/api/v1/dashboard/devices/$deviceId/config');
    final response = await _client.put(
      url,
      headers: await _headers(),
      body: jsonEncode(configBody),
    );
    _handleResponse(response);
    return true;
  }

  // --- Device Sharing ---

  /// Fetches everyone the owner has given view-only access to (owner-only;
  /// the API returns 403 for a shared, non-owning viewer).
  Future<({List<DeviceShare> shares, int maxShares})> getDeviceShares(String deviceId) async {
    final url = Uri.parse('$baseUrl/api/v1/dashboard/devices/$deviceId/shares');
    final response = await _client.get(url, headers: await _headers());
    final data = _handleResponse(response);
    final list = data['shares'] as List<dynamic>? ?? [];
    return (
      shares: list.map((item) => DeviceShare.fromJson(item as Map<String, dynamic>)).toList(),
      maxShares: data['maxShares'] as int? ?? 5,
    );
  }

  /// Grants view-only access to another JKBMSR account by email. Throws with
  /// the server's message on failure (no account with that email, already
  /// shared, or the per-device share cap reached).
  Future<DeviceShare> addDeviceShare(String deviceId, String email) async {
    final url = Uri.parse('$baseUrl/api/v1/dashboard/devices/$deviceId/shares');
    final response = await _client.post(
      url,
      headers: await _headers(),
      body: jsonEncode({'email': email}),
    );
    final data = _handleResponse(response) as Map<String, dynamic>;
    return DeviceShare(userId: data['userId'] as String, email: data['email'] as String, sharedAt: '');
  }

  /// Revokes a previously-granted share. Idempotent from the caller's
  /// perspective: a 404 here just means it was already revoked.
  Future<void> revokeDeviceShare(String deviceId, String userId) async {
    final url = Uri.parse('$baseUrl/api/v1/dashboard/devices/$deviceId/shares/$userId');
    final response = await _client.delete(url, headers: await _headers());
    _handleResponse(response);
  }

  // --- WiFi Management ---

  /// Fetches the gateway's current WiFi status plus any in-flight scan or
  /// change request. Owner-only.
  Future<DeviceWifiState> getDeviceWifi(String deviceId) async {
    final url = Uri.parse('$baseUrl/api/v1/dashboard/devices/$deviceId/wifi');
    final response = await _client.get(url, headers: await _headers());
    final data = _handleResponse(response) as Map<String, dynamic>;
    return DeviceWifiState.fromJson(data['wifi'] as Map<String, dynamic>);
  }

  /// Queues an async 2.4 GHz network scan on the gateway — it picks the
  /// request up on its own poll cycle, typically within a minute. Poll
  /// [getDeviceWifi] afterward for `scanCompletedAt` to know when done.
  Future<String> requestWifiScan(String deviceId) async {
    final url = Uri.parse('$baseUrl/api/v1/dashboard/devices/$deviceId/wifi/scan');
    final response = await _client.post(url, headers: await _headers());
    final data = _handleResponse(response) as Map<String, dynamic>;
    return data['requestId'] as String;
  }

  /// Queues an async WiFi credential change. The gateway restores its
  /// previous network automatically if the new one can't reach JKBMSR
  /// Cloud — poll [getDeviceWifi] for `changeStatus` to track the result.
  Future<void> requestWifiChange(String deviceId, String ssid, String password) async {
    final url = Uri.parse('$baseUrl/api/v1/dashboard/devices/$deviceId/wifi/change');
    final response = await _client.post(
      url,
      headers: await _headers(),
      body: jsonEncode({'ssid': ssid, 'password': password}),
    );
    _handleResponse(response);
  }

  // --- Sessions ---

  /// Recent sign-ins for the account. Each one doubles as a live/revocable
  /// session where the backend tracked it (see [revokeSession]) — older
  /// history rows or ones from a reissued-in-place token just show as
  /// informational and won't offer a sign-out action.
  Future<List<RecentSession>> getRecentSessions() async {
    final url = Uri.parse('$baseUrl/api/v1/user/sessions');
    final response = await _client.get(url, headers: await _headers());
    final data = _handleResponse(response);
    final list = data['logins'] as List<dynamic>? ?? [];
    return list.map((item) => RecentSession.fromJson(item as Map<String, dynamic>)).toList();
  }

  /// Signs out one specific session. Returns true if it was this device's
  /// own current session (the caller should then clear local auth and
  /// return to login, since there's no valid token left to continue with).
  Future<bool> revokeSession(String sessionId) async {
    final url = Uri.parse('$baseUrl/api/v1/user/sessions/$sessionId/revoke');
    final response = await _client.post(url, headers: await _headers());
    final data = _handleResponse(response) as Map<String, dynamic>;
    return data['wasCurrent'] as bool? ?? false;
  }

  /// Signs out every other device/browser signed into this account, and
  /// returns a fresh token for the current session (same one — the server
  /// reissues in place rather than logging this device out too).
  Future<String> revokeOtherSessions() async {
    final url = Uri.parse('$baseUrl/api/v1/user/sessions/revoke');
    final response = await _client.post(url, headers: await _headers());
    final data = _handleResponse(response) as Map<String, dynamic>;
    return data['token'] as String;
  }

  /// Deletes (not just marks revoked) every sign-in record whose session
  /// has already expired — pure housekeeping so the Recent Sign-ins list
  /// doesn't grow forever with stale rows. Returns how many were removed.
  Future<int> clearExpiredSessions() async {
    final url = Uri.parse('$baseUrl/api/v1/user/sessions/clear-expired');
    final response = await _client.post(url, headers: await _headers());
    final data = _handleResponse(response) as Map<String, dynamic>;
    return data['clearedCount'] as int? ?? 0;
  }

  /// Empties the sign-in history — expired and signed-out records alike — while
  /// keeping the current session. Returns how many rows were removed.
  Future<int> clearAllSessions() async {
    final url = Uri.parse('$baseUrl/api/v1/user/sessions/clear-all');
    final response = await _client.post(url, headers: await _headers());
    final data = _handleResponse(response) as Map<String, dynamic>;
    return data['clearedCount'] as int? ?? 0;
  }

  // --- OTA ---

  /// Fetches the check/log history of OTA updates.
  Future<List<OtaEvent>> getOtaHistory(String deviceId, {int limit = 20}) {
    return deduplicate('ota_history_$deviceId', () async {
      final cacheKey = 'ota_history_$deviceId';
      try {
        final url = Uri.parse('$baseUrl/api/v1/dashboard/devices/$deviceId/ota/history?limit=$limit');
        final response = await _client.get(url, headers: await _headers());
        final data = _handleResponse(response);
        await CacheService.instance.cacheData(cacheKey, data);
        final list = data['events'] as List<dynamic>? ?? [];
        return list.map((item) => OtaEvent.fromJson(item as Map<String, dynamic>)).toList();
      } catch (e) {
        final cached = await CacheService.instance.getCachedData(cacheKey);
        if (cached != null) {
          final list = cached['events'] as List<dynamic>? ?? [];
          return list.map((item) => OtaEvent.fromJson(item as Map<String, dynamic>)).toList();
        }
        rethrow;
      }
    });
  }

  /// Latest 10 successful BLE polls — reused from telemetry server-side
  /// (see the API route), so there's no separate limit param to pass.
  Future<List<BleHistoryEvent>> getBleHistory(String deviceId) {
    return deduplicate('ble_history_$deviceId', () async {
      final cacheKey = 'ble_history_$deviceId';
      try {
        final url = Uri.parse('$baseUrl/api/v1/dashboard/devices/$deviceId/ble/history');
        final response = await _client.get(url, headers: await _headers());
        final data = _handleResponse(response);
        await CacheService.instance.cacheData(cacheKey, data);
        final list = data['events'] as List<dynamic>? ?? [];
        return list.map((item) => BleHistoryEvent.fromJson(item as Map<String, dynamic>)).toList();
      } catch (e) {
        final cached = await CacheService.instance.getCachedData(cacheKey);
        if (cached != null) {
          final list = cached['events'] as List<dynamic>? ?? [];
          return list.map((item) => BleHistoryEvent.fromJson(item as Map<String, dynamic>)).toList();
        }
        rethrow;
      }
    });
  }

  /// Requests an immediate OTA check on the gateway. The API queues the
  /// command and returns a request id; the device performs the check on its
  /// next poll.
  Future<Map<String, dynamic>> requestOtaCheck(String deviceId) async {
    final url = Uri.parse('$baseUrl/api/v1/dashboard/devices/$deviceId/ota/check');
    final response = await _client.post(url, headers: await _headers());
    return _handleResponse(response) as Map<String, dynamic>;
  }

  /// Reads the current queued OTA command state for a gateway.
  Future<Map<String, dynamic>?> getOtaCommand(String deviceId) async {
    final url = Uri.parse('$baseUrl/api/v1/dashboard/devices/$deviceId/ota/command');
    final response = await _client.get(url, headers: await _headers());
    final data = _handleResponse(response) as Map<String, dynamic>;
    return data['command'] as Map<String, dynamic>?;
  }

  /// Fetches the same firmware release visibility data shown on the web
  /// dashboard: version, target hardware, rollout channel, release date, and
  /// public-mirror verification state. Optionally scoped to a target
  /// hardware/rollout channel (typically the selected device's own).
  Future<List<FirmwareRelease>> getFirmwareReleases({
    String? targetHardware,
    String? rolloutChannel,
    int limit = 10,
  }) {
    return deduplicate('firmware_releases_${targetHardware ?? 'all'}_${rolloutChannel ?? 'all'}', () async {
      final cacheKey = 'firmware_releases_${targetHardware ?? 'all'}_${rolloutChannel ?? 'all'}';
      final query = <String, String>{'limit': '$limit'};
      if (targetHardware != null && targetHardware.isNotEmpty) {
        query['targetHardware'] = targetHardware;
      }
      if (rolloutChannel != null && rolloutChannel.isNotEmpty) {
        query['rolloutChannel'] = rolloutChannel;
      }
      try {
        final url = Uri.parse('$baseUrl/api/v1/dashboard/firmware/releases').replace(queryParameters: query);
        final response = await _client.get(url, headers: await _headers());
        final data = _handleResponse(response);
        await CacheService.instance.cacheData(cacheKey, data);
        final list = data['releases'] as List<dynamic>? ?? [];
        return list.map((item) => FirmwareRelease.fromJson(item as Map<String, dynamic>)).toList();
      } catch (e) {
        final cached = await CacheService.instance.getCachedData(cacheKey);
        if (cached != null) {
          final list = cached['releases'] as List<dynamic>? ?? [];
          return list.map((item) => FirmwareRelease.fromJson(item as Map<String, dynamic>)).toList();
        }
        rethrow;
      }
    });
  }

  // --- Push Notifications ---

  /// Upserts this install's FCM token and current notification preferences
  /// with the signed-in account. Safe to call on every token refresh and
  /// every preference change — the server treats it as a full replace of
  /// this token's row, keyed by the token itself.
  Future<void> registerPushToken({
    required String token,
    required String platform,
    required bool criticalAlerts,
    required bool temperatureAlerts,
    required bool offlineAlerts,
    required bool warningAlerts,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/user/notifications/register');
    final response = await _client.post(
      url,
      headers: await _headers(),
      body: jsonEncode({
        'token': token,
        'platform': platform,
        'criticalAlerts': criticalAlerts,
        'temperatureAlerts': temperatureAlerts,
        'offlineAlerts': offlineAlerts,
        'warningAlerts': warningAlerts,
      }),
    );
    _handleResponse(response);
  }

  /// Removes a device token from the signed-in account, e.g. on sign-out.
  Future<void> unregisterPushToken(String token) async {
    final url = Uri.parse('$baseUrl/api/v1/user/notifications/register');
    final request = http.Request('DELETE', url)
      ..headers.addAll(await _headers())
      ..body = jsonEncode({'token': token});
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    _handleResponse(response);
  }
}
