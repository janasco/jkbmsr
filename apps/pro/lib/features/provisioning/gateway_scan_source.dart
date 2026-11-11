import 'dart:async';

import 'discovered_gateway.dart';

/// Why a scan could not start.
///
/// Each one has a different fix, so they are separate states rather than one
/// "scan failed": telling a user to enable Bluetooth when the real problem is a
/// denied permission is the exact class of message this app avoids.
enum ScanFailure {
  bluetoothOff,
  permissionDenied,
  unsupported,
}

/// The seam between the scan screen and the radio.
///
/// The screen is built against this, not against a BLE package, so the whole
/// flow can be widget-tested with a fake and the radio can be swapped in
/// without touching the UI. Same shape as the scan window seam in the BLE app,
/// which exists because a widget test that never settles does not fail fast, it
/// burns ten minutes.
abstract class GatewayScanSource {
  /// Every gateway currently advertising. Re-emitted as the set changes.
  Stream<List<DiscoveredGateway>> get results;

  /// Starts scanning. Returns the reason it could not, or null when scanning.
  Future<ScanFailure?> start();

  Future<void> stop();

  void dispose();
}

/// The default until the BLE stack is wired in.
///
/// Deliberately says so instead of returning an empty list: an empty scan looks
/// identical to "there is no gateway nearby", and would send the owner looking
/// at their hardware for a software gap.
class UnavailableGatewayScanSource implements GatewayScanSource {
  final _controller = StreamController<List<DiscoveredGateway>>.broadcast();

  @override
  Stream<List<DiscoveredGateway>> get results => _controller.stream;

  @override
  Future<ScanFailure?> start() async => ScanFailure.unsupported;

  @override
  Future<void> stop() async {}

  @override
  void dispose() {
    _controller.close();
  }
}

/// A scripted source for tests and for local UI work. Not registered anywhere in
/// the app.
class FakeGatewayScanSource implements GatewayScanSource {
  FakeGatewayScanSource({
    this.failure,
    List<DiscoveredGateway> initial = const [],
    this.startDelay = Duration.zero,
  }) : _gateways = [...initial];

  final ScanFailure? failure;
  final Duration startDelay;
  final List<DiscoveredGateway> _gateways;
  final _controller = StreamController<List<DiscoveredGateway>>.broadcast();

  int startCalls = 0;
  int stopCalls = 0;
  bool disposed = false;

  @override
  Stream<List<DiscoveredGateway>> get results => _controller.stream;

  @override
  Future<ScanFailure?> start() async {
    startCalls++;
    if (startDelay > Duration.zero) {
      await Future<void>.delayed(startDelay);
    }
    if (failure != null) return failure;
    _emit();
    return null;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  /// Pushes a new set, as the radio would.
  void add(DiscoveredGateway gateway) {
    _gateways.add(gateway);
    _emit();
  }

  void remove(String id) {
    _gateways.removeWhere((g) => g.id == id);
    _emit();
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(List.unmodifiable(_gateways));
  }

  @override
  void dispose() {
    disposed = true;
    _controller.close();
  }
}
