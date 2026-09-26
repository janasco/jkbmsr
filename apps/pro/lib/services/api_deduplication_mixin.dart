import 'dart:async';
import 'request_deduplication.dart';

/// Mixin that adds request deduplication to API client methods.
/// Use this to prevent multiple simultaneous calls to the same endpoint.
///
/// Usage:
/// ```dart
/// class MyApiClient with ApiDeduplicationMixin {
///   Future<List<Device>> getDevices() async {
///     return deduplicate('device_list', () async {
///       // actual API call
///     });
///   }
/// }
/// ```
mixin ApiDeduplicationMixin {
  /// Execute a request with deduplication. If a request with the same
  /// [key] is already in flight, the new caller waits for the existing
  /// request to complete instead of making a duplicate call.
  Future<T> deduplicate<T>(
    String key,
    Future<T> Function() request, {
    Duration ttl = const Duration(seconds: 5),
  }) {
    return RequestDeduplication.instance.deduplicate<T>(key, request, ttl: ttl);
  }

  /// Check if a request with the given key is currently in flight.
  bool isInFlight(String key) {
    return RequestDeduplication.instance.isInFlight(key);
  }
}
