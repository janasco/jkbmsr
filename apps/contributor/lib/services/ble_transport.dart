/// The narrow BLE seam the capture logic talks to.
///
/// The real implementation is [FlutterBluePlusTransport]; tests use a fake so
/// the frame-reassembly, decoding and payload-building logic can be exercised
/// without a radio. Everything protocol-specific stays in `bms_core` and
/// everything plugin-specific stays in the concrete transport.
library;

import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;

/// One discovered BLE device, reduced to what the capture flow needs.
class BleScanResult {
  /// Platform device id. On Android this is the MAC address (which the
  /// payload anonymiser reduces to its OUI); on iOS it is a per-device UUID.
  final String id;
  final String name;
  final int rssi;
  final bool connectable;

  /// Advertised GATT service UUIDs, lower-cased 128-bit form.
  final List<String> serviceUuids;

  const BleScanResult({
    required this.id,
    required this.name,
    required this.rssi,
    this.connectable = true,
    this.serviceUuids = const [],
  });

  /// Whether this looks like a JK-BMS from its advertised name or a JK GATT
  /// service. The name test is the authoritative one; the service test is the
  /// same name-independent fallback `apps/ble` uses for blank/renamed modules.
  bool get looksLikeJk => serviceUuids.any((u) => _jkServiceUuids.contains(u));
}

const Set<String> _jkServiceUuids = {
  '0000ffe0-0000-1000-8000-00805f9b34fb',
  '0000ff00-0000-1000-8000-00805f9b34fb',
};

/// A connected device with the BMS notify/write characteristics already bound.
abstract interface class BleSession {
  String get deviceName;
  int get rssi;
  List<String> get serviceUuids;

  /// Notification payloads, in arrival order, exactly as the hardware sent
  /// them (usually small fragments of a 300-byte JK02 frame).
  Stream<List<int>> get notifications;

  /// Writes a command to the BMS write characteristic.
  Future<void> write(List<int> data);

  /// Disconnects and releases the session.
  Future<void> disconnect();
}

/// Scan/connect transport, injectable for tests.
abstract interface class BleTransport {
  /// Whether BLE is available on this device.
  Future<bool> isSupported();

  /// Starts a scan and emits the accumulated list of JK-plausible devices
  /// until [timeout] elapses. Each emission is a fresh snapshot.
  Stream<List<BleScanResult>> scan({Duration timeout});

  /// Connects to [deviceId] and binds the BMS notify/write characteristics.
  Future<BleSession> connect(String deviceId);
}

/// Why a scan could not start, in terms the UI can act on.
///
/// Bluetooth being switched off is an **expected, common state**, not a
/// failure: classifying it here (rather than letting the plugin's raw
/// exception reach the screen) is what lets the UI show plain, actionable copy
/// and a retry instead of `PlatformException(...)`.
enum BleScanFailureKind {
  /// The device's Bluetooth adapter is switched off.
  bluetoothOff,

  /// The scan permission was not granted.
  permissionDenied,

  /// Android needs Location Services enabled before it will scan.
  locationServicesOff,

  /// The hardware has no Bluetooth LE support.
  unsupported,

  /// Anything else, still surfaced as a sentence rather than swallowed.
  other,
}

/// A scan failure translated out of the plugin's raw exception.
///
/// [cause] keeps the original error so the transport can record the real reason
/// in the logs; the user-facing sentence comes from
/// `ScanStrings.scanFailure(kind)`, so a `PlatformException`'s `toString()`
/// never reaches the product.
class BleScanException implements Exception {
  const BleScanException(this.kind, {this.cause});

  final BleScanFailureKind kind;

  /// The original error, for logging only — never shown to the user.
  final Object? cause;

  @override
  String toString() => 'BleScanException(${kind.name}, cause: $cause)';
}

/// Classifies a raw error thrown while starting a scan.
///
/// Detection uses the plugin exception's `code`/`message` (Android says
/// "Bluetooth must be turned on", iOS/Android permission and location errors
/// name themselves). An unknown failure maps to [BleScanFailureKind.other]
/// rather than being rethrown, so a scan failure is always surfaced as an
/// actionable condition and never silently swallowed.
BleScanException classifyScanFailure(Object error) {
  if (error is BleScanException) return error;

  var code = '';
  var message = '';
  if (error is PlatformException) {
    code = error.code;
    message = error.message ?? '';
  }
  // `FlutterBluePlusException.toString()` also names the function/code, so the
  // whole error text is searched, not just the PlatformException fields.
  final haystack = '$code $message $error'.toLowerCase();

  if (haystack.contains('must be turned on')) {
    return BleScanException(BleScanFailureKind.bluetoothOff, cause: error);
  }
  if (haystack.contains('location services')) {
    return BleScanException(BleScanFailureKind.locationServicesOff, cause: error);
  }
  if (haystack.contains('permission') || haystack.contains('unauthori')) {
    return BleScanException(BleScanFailureKind.permissionDenied, cause: error);
  }
  if (haystack.contains('does not support bluetooth') ||
      code.toLowerCase() == 'bluetoothunavailable') {
    return BleScanException(BleScanFailureKind.unsupported, cause: error);
  }
  return BleScanException(BleScanFailureKind.other, cause: error);
}
