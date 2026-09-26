import 'dart:async';

/// Request deduplication service that prevents multiple simultaneous
/// calls to the same endpoint. Useful for avoiding redundant API calls
/// when multiple screens or widgets request the same data concurrently.
class RequestDeduplication {
  static final RequestDeduplication instance = RequestDeduplication._();
  RequestDeduplication._();

  final Map<String, Completer<dynamic>> _inFlightRequests = {};

  /// Execute a request with deduplication. If a request with the same
  /// [key] is already in flight, the new caller waits for the existing
  /// request to complete instead of making a duplicate call.
  ///
  /// [key] — A unique identifier for this request (e.g., 'device_list',
  ///          'telemetry_device_123', 'alerts_active').
  /// [request] — The async function that performs the actual API call.
  /// [ttl] — Optional time-to-live for the deduplication window.
  ///          Defaults to 5 seconds. After this time, a new request
  ///          will be allowed even if the previous one is still in flight.
  Future<T> deduplicate<T>(
    String key,
    Future<T> Function() request, {
    Duration ttl = const Duration(seconds: 5),
  }) async {
    // If there's already an in-flight request with this key, wait for it
    final existing = _inFlightRequests[key];
    if (existing != null) {
      try {
        return await existing.future as T;
      } catch (_) {
        // If the existing request failed, allow a new one
      }
    }

    // Create a new completer and execute the request
    final completer = Completer<dynamic>();
    // Concurrent callers awaiting this completer must still see a failure, but
    // when there is no such caller a completed error has no listener and Dart
    // reports it as an unhandled async error -- an extra Crashlytics/log entry
    // for every failed deduplicated request, on top of the one the original
    // caller already handles. Swallowing on this derived future marks it
    // handled; `completer.future` itself still delivers the error to any real
    // awaiter.
    unawaited(completer.future.catchError((Object _) => null));
    _inFlightRequests[key] = completer;

    // Set up TTL timeout to prevent permanent blocking
    Timer(ttl, () {
      if (!completer.isCompleted) {
        _inFlightRequests.remove(key);
      }
    });

    try {
      final result = await request();
      if (!completer.isCompleted) {
        completer.complete(result);
      }
      return result;
    } catch (e) {
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
      rethrow;
    } finally {
      _inFlightRequests.remove(key);
    }
  }

  /// Cancel all in-flight deduplicated requests.
  void cancelAll() {
    for (final completer in _inFlightRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError('Request cancelled');
      }
    }
    _inFlightRequests.clear();
  }

  /// Cancel a specific in-flight request by key.
  void cancel(String key) {
    final completer = _inFlightRequests.remove(key);
    if (completer != null && !completer.isCompleted) {
      completer.completeError('Request cancelled');
    }
  }

  /// Check if a request with the given key is currently in flight.
  bool isInFlight(String key) {
    final completer = _inFlightRequests[key];
    return completer != null && !completer.isCompleted;
  }
}

/// Convenience mixin exposing [RequestDeduplication.deduplicate] and
/// [RequestDeduplication.isInFlight] to classes that issue API calls
/// (e.g. the APIClient singleton) without reaching into the singleton/// directly at every call site.
mixin RequestDeduplicationMixin {
  Future<T> deduplicate<T>(
    String key,
    Future<T> Function() request, {
    Duration ttl = const Duration(seconds: 5),
  }) {
    return RequestDeduplication.instance.deduplicate<T>(key, request, ttl: ttl);
  }

  bool isInFlight(String key) {
    return RequestDeduplication.instance.isInFlight(key);
  }
}
