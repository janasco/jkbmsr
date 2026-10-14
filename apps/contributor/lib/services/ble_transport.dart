/// The narrow BLE seam the capture logic talks to.
///
/// The real implementation is [FlutterBluePlusTransport]; tests use a fake so
/// the frame-reassembly, decoding and payload-building logic can be exercised
/// without a radio. Everything protocol-specific stays in `bms_core` and
/// everything plugin-specific stays in the concrete transport.
library;

import 'dart:async';

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
