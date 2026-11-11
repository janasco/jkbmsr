import 'dart:async';

import 'package:universal_ble/universal_ble.dart';

import 'discovered_gateway.dart';
import 'gateway_scan_source.dart';
import 'provisioning_protocol.dart';

/// Scanning for a gateway that is advertising its setup service.
///
/// Only a gateway that cannot reach the network advertises, so a result here is
/// always a gateway that wants setting up. The filter is the service UUID with
/// the name prefix as a second condition: the UUID is the contract, and the name
/// is what the user sees, so a device advertising one without the other is not
/// shown as a candidate.
class BleGatewayScanSource implements GatewayScanSource {
  BleGatewayScanSource({this.emitDebounce = const Duration(milliseconds: 250)});

  /// Results arrive per advertising packet, and every packet would rebuild the
  /// list. A short debounce turns a burst into one frame.
  final Duration emitDebounce;

  final _controller = StreamController<List<DiscoveredGateway>>.broadcast();
  final Map<String, DiscoveredGateway> _seen = {};
  Timer? _emitTimer;
  bool _scanning = false;

  @override
  Stream<List<DiscoveredGateway>> get results => _controller.stream;

  @override
  Future<ScanFailure?> start() async {
    if (_scanning) return null;

    try {
      await UniversalBle.requestPermissions();
    } catch (_) {
      return ScanFailure.permissionDenied;
    }

    _seen.clear();
    UniversalBle.onScanResult = _onScanResult;

    try {
      await UniversalBle.startScan(
        scanFilter: ScanFilter(
          withServices: [ProvisioningProtocol.service],
          withNamePrefix: [ProvisioningProtocol.namePrefix],
          connectableOnly: true,
        ),
      );
      _scanning = true;
      return null;
    } catch (error) {
      UniversalBle.onScanResult = null;
      // The two failures with different fixes. A platform error that names
      // neither is reported as unsupported rather than guessed at.
      final message = error.toString().toLowerCase();
      if (message.contains('permission') || message.contains('denied')) {
        return ScanFailure.permissionDenied;
      }
      if (message.contains('bluetooth') || message.contains('adapter')) {
        return ScanFailure.bluetoothOff;
      }
      return ScanFailure.unsupported;
    }
  }

  void _onScanResult(BleDevice device) {
    final name = device.name ?? device.rawName ?? '';
    if (!name.startsWith(ProvisioningProtocol.namePrefix)) {
      return;
    }
    _seen[device.deviceId] = DiscoveredGateway(
      id: device.deviceId,
      name: name,
      // A device that did not report RSSI is shown at the weakest bar rather
      // than a made-up middle value.
      rssi: device.rssi ?? -100,
    );
    _scheduleEmit();
  }

  void _scheduleEmit() {
    if (_emitTimer?.isActive ?? false) return;
    _emitTimer = Timer(emitDebounce, () {
      if (!_controller.isClosed) {
        _controller.add(List.unmodifiable(_seen.values.toList()));
      }
    });
  }

  @override
  Future<void> stop() async {
    _emitTimer?.cancel();
    _scanning = false;
    UniversalBle.onScanResult = null;
    try {
      await UniversalBle.stopScan();
    } catch (_) {
      // Stopping a scan that already stopped is not a failure worth surfacing.
    }
  }

  @override
  void dispose() {
    _emitTimer?.cancel();
    _controller.close();
  }
}
