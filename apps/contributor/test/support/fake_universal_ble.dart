import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

/// A no-op [UniversalBlePlatform] so widget tests can mount the app on the Dart
/// VM, where the plugin has no platform implementation and installing one that
/// throws would fail the first `scanStream` listen.
///
/// Everything here is inert on purpose: the adapter is present, nothing is
/// discovered, and no connection can be made, so the screens render their real
/// idle or empty states deterministically. The transport's own behaviour is
/// covered in `test/services/universal_ble_transport_test.dart`, which
/// installs a fake that does drive the radio.
final class FakeUniversalBlePlatform extends UniversalBlePlatform {
  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async => AvailabilityState.poweredOn;

  @override
  Future<void> startScan({ScanFilter? scanFilter, PlatformConfig? platformConfig}) async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<bool> isScanning() async => false;

  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    updateConnection(deviceId, true);
  }

  @override
  Future<void> disconnect(String deviceId) async => updateConnection(deviceId, false);

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async => BleConnectionState.disconnected;

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors, {
    DiscoverServicesPlatformConfig? platformConfig,
  }) async =>
      const [];

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {}

  @override
  Future<Uint8List> readValue(String deviceId, String service, String characteristic, {Duration? timeout}) async => Uint8List(0);

  @override
  Future<Uint8List> readDescriptorValue(String deviceId, String service, String characteristic, String descriptor, {Duration? timeout}) async => Uint8List(0);

  @override
  Future<void> writeValue(String deviceId, String service, String characteristic, Uint8List value, BleOutputProperty bleOutputProperty) async {}

  @override
  Future<void> writeDescriptorValue(String deviceId, String service, String characteristic, String descriptor, Uint8List value) async {}

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async => expectedMtu;

  @override
  Future<int> readRssi(String deviceId) async => 0;

  @override
  Future<bool> enableBluetooth() async => true;

  @override
  Future<bool> disableBluetooth() async => true;

  @override
  Future<void> requestConnectionPriority(String deviceId, BleConnectionPriority priority) async {}

  @override
  Future<bool> isPaired(String deviceId) async => false;

  @override
  Future<bool> pair(String deviceId) async => true;

  @override
  Future<void> unpair(String deviceId) async {}

  @override
  Future<List<BleDevice>> getSystemDevices(List<String>? withServices) async => const [];
}

/// Installs the fake for the current test.
void installFakeUniversalBle() {
  UniversalBle.setInstance(FakeUniversalBlePlatform());
}
