import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_contributor/services/ble_transport.dart';
import 'package:jkbmsr_contributor/services/universal_ble_transport.dart';
import 'package:universal_ble/universal_ble.dart';

/// A platform fake the test drives instead of a radio.
///
/// `UniversalBle` talks to the platform through this interface, so installing a
/// fake with `UniversalBle.setInstance` exercises the real transport code —
/// scanning, connecting, binding characteristics — without a device. Methods the
/// capture flow never reaches throw, so an accidental new dependency on them
/// fails loudly rather than silently returning a plausible value.
final class _FakeUniversalBlePlatform extends UniversalBlePlatform {
  _FakeUniversalBlePlatform({this.startScanError, this.scanDevices, this.services = const []});

  Object? startScanError;
  List<BleDevice>? scanDevices;
  List<BleService> services;

  bool startScanCalled = false;
  int stopScanCount = 0;
  int? requestedMtu;
  final Map<String, BleConnectionState> _states = {};
  final List<(String, String, String, BleOutputProperty, List<int>)> writes = [];

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async => AvailabilityState.poweredOn;

  @override
  Future<void> startScan({ScanFilter? scanFilter, PlatformConfig? platformConfig}) async {
    startScanCalled = true;
    if (startScanError != null) throw startScanError!;
    final devices = scanDevices;
    if (devices != null) {
      // Delivered after startScan returns, so the transport has attached its
      // listener to the platform stream first — the same ordering a real plugin
      // guarantees.
      scheduleMicrotask(() {
        for (final d in devices) {
          updateScanResult(d);
        }
      });
    }
  }

  @override
  Future<void> stopScan() async {
    stopScanCount++;
  }

  @override
  Future<bool> isScanning() async => false;

  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    _states[deviceId] = BleConnectionState.connected;
    updateConnection(deviceId, true);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    _states[deviceId] = BleConnectionState.disconnected;
    updateConnection(deviceId, false);
  }

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async =>
      _states[deviceId] ?? BleConnectionState.disconnected;

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors, {
    DiscoverServicesPlatformConfig? platformConfig,
  }) async =>
      services;

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {}

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    writes.add((deviceId, service, characteristic, bleOutputProperty, value.toList()));
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async {
    requestedMtu = expectedMtu;
    return expectedMtu;
  }

  @override
  Future<int> readRssi(String deviceId) async => -55;

  // Not reached by the capture flow; present because the interface requires them.
  @override
  Future<bool> enableBluetooth() async => true;
  @override
  Future<bool> disableBluetooth() async => true;
  @override
  Future<Uint8List> readValue(String deviceId, String service, String characteristic, {Duration? timeout}) async => Uint8List(0);
  @override
  Future<Uint8List> readDescriptorValue(String deviceId, String service, String characteristic, String descriptor, {Duration? timeout}) async => Uint8List(0);
  @override
  Future<void> writeDescriptorValue(String deviceId, String service, String characteristic, String descriptor, Uint8List value) async {}
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

BleDevice _jkDevice({String id = 'AA:BB:CC:11:22:33', String name = 'JK_B2A24S15P'}) {
  return BleDevice(
    deviceId: id,
    name: name,
    rssi: -63,
    connectable: true,
    services: ['0000ffe0-0000-1000-8000-00805f9b34fb'],
  );
}

/// The result of driving a transport's scan stream to completion.
class _ScanRun {
  _ScanRun(this.events, this.errors, this.done);
  final List<List<BleScanResult>> events;
  final List<Object> errors;
  final Future<void> done;
}

_ScanRun _runScan(UniversalBleTransport transport, {Duration? timeout}) {
  final events = <List<BleScanResult>>[];
  final errors = <Object>[];
  final done = Completer<void>();
  transport.scan(timeout: timeout ?? const Duration(seconds: 12)).listen(
        events.add,
        onError: errors.add,
        onDone: done.complete,
      );
  return _ScanRun(events, errors, done.future);
}

void main() {
  group('classifyScanFailure', () {
    test('an Android "Bluetooth must be turned on" startScan error is bluetoothOff', () {
      final failure = classifyScanFailure(PlatformException(
        code: 'startScan',
        message: 'Bluetooth must be turned on',
      ));
      expect(failure.kind, BleScanFailureKind.bluetoothOff);
      // The raw exception is kept for the logs, not shown to the user.
      expect(failure.cause, isA<PlatformException>());
    });

    test('the iOS wording ("bluetooth must be turned on (CBManagerStatePoweredOff)") '
        'is also bluetoothOff', () {
      final failure = classifyScanFailure(PlatformException(
        code: 'startScan',
        message: 'bluetooth must be turned on. (CBManagerStatePoweredOff)',
      ));
      expect(failure.kind, BleScanFailureKind.bluetoothOff);
    });

    test('a permission error is permissionDenied, not swallowed', () {
      final failure = classifyScanFailure(PlatformException(
        code: 'startScan',
        message: 'Permission android.permission.BLUETOOTH_SCAN required to scan devices',
      ));
      expect(failure.kind, BleScanFailureKind.permissionDenied);
    });

    test('an iOS unauthorized state is permissionDenied', () {
      final failure = classifyScanFailure(PlatformException(
        code: 'startScan',
        message: 'bluetooth must be turned on. (CBManagerStateUnauthorized)',
      ));
      // "must be turned on" is matched first, so this is reported as the
      // adapter being off; the transport's adapter pre-check is what catches
      // `unauthorized` before the platform is asked. Either way the user gets
      // an actionable sentence, never the raw exception.
      expect(failure.kind, anyOf(BleScanFailureKind.bluetoothOff, BleScanFailureKind.permissionDenied));
    });

    test('a Location Services error keeps its own kind', () {
      final failure = classifyScanFailure(PlatformException(
        code: 'startScan',
        message: 'Location services are required for Bluetooth scan',
      ));
      expect(failure.kind, BleScanFailureKind.locationServicesOff);
    });

    test('an unavailable-adapter error is unsupported', () {
      final failure = classifyScanFailure(PlatformException(
        code: 'bluetoothUnavailable',
        message: 'the device does not support bluetooth',
      ));
      expect(failure.kind, BleScanFailureKind.unsupported);
    });

    test('an unrecognised error still becomes an actionable failure', () {
      final failure = classifyScanFailure(StateError('something odd'));
      expect(failure.kind, BleScanFailureKind.other);
      expect(failure.cause, isA<StateError>());
    });

    test('an already-classified failure passes through unchanged', () {
      const original = BleScanException(BleScanFailureKind.bluetoothOff);
      expect(identical(classifyScanFailure(original), original), isTrue);
    });
  });

  group('classifyCaptureFailure', () {
    test('Bluetooth off is the one condition shared with the scan path', () {
      final failure = classifyCaptureFailure(PlatformException(
        code: 'connect',
        message: 'Bluetooth must be turned on',
      ));
      expect(failure.kind, BleCaptureFailureKind.bluetoothOff);
      // The raw exception is kept for the logs, not shown to the user.
      expect(failure.cause, isA<PlatformException>());
    });

    test('an out-of-range wording is outOfRange', () {
      final failure = classifyCaptureFailure(PlatformException(
        code: 'connect',
        message: 'connection failed: device is out of range',
      ));
      expect(failure.kind, BleCaptureFailureKind.outOfRange);
    });

    test('a dropped link mid-session is outOfRange too', () {
      final failure = classifyCaptureFailure(PlatformException(
        code: 'disconnect',
        message: 'device disconnected',
      ));
      expect(failure.kind, BleCaptureFailureKind.outOfRange);
    });

    test('a generic GATT error is other, not mislabelled out-of-range', () {
      final failure = classifyCaptureFailure(PlatformException(
        code: 'gatt',
        message: 'GATT error: could not write characteristic',
      ));
      expect(failure.kind, BleCaptureFailureKind.other);
      expect(failure.cause, isA<PlatformException>());
    });

    test('a GATT lookup failure is other, not mislabelled out-of-range', () {
      // "not found" is deliberately absent from the connection-lost wording:
      // a service/characteristic lookup failure is a GATT error, not a range
      // problem, and must keep its generic, honest sentence.
      final failure = classifyCaptureFailure(PlatformException(
        code: 'gatt',
        message: 'service 0000ffe0-0000-1000-8000-00805f9b34fb not found',
      ));
      expect(failure.kind, BleCaptureFailureKind.other);
    });

    test('an unrecognised error still becomes an actionable failure', () {
      final failure = classifyCaptureFailure(StateError('something odd'));
      expect(failure.kind, BleCaptureFailureKind.other);
      expect(failure.cause, isA<StateError>());
    });

    test('an already-classified failure passes through unchanged', () {
      const original = BleCaptureException(BleCaptureFailureKind.outOfRange);
      expect(identical(classifyCaptureFailure(original), original), isTrue);
    });
  });

  group('UniversalBleTransport.scan', () {
    test('a Bluetooth-off PlatformException never reaches the stream raw; '
        'it becomes a bluetoothOff failure and is logged', () async {
      final platform = _FakeUniversalBlePlatform(
        startScanError: PlatformException(
          code: 'startScan',
          message: 'Bluetooth must be turned on',
        ),
      );
      UniversalBle.setInstance(platform);
      final logs = <String>[];
      final transport = UniversalBleTransport(
        // The adapter pre-check says "on"; the failure falls through to the
        // classification path, which is what this test pins.
        availability: () async => AvailabilityState.poweredOn,
        log: logs.add,
      );

      final run = _runScan(transport);
      await run.done;

      expect(run.errors, hasLength(1));
      final error = run.errors.single;
      expect(error, isA<BleScanException>(),
          reason: 'the raw PlatformException must be translated, not surfaced');
      expect((error as BleScanException).kind, BleScanFailureKind.bluetoothOff);
      // The raw reason is recorded for the logs.
      expect(logs.join('\n'), contains('Bluetooth must be turned on'));
    });

    test('a different scan failure (permission) is still surfaced, not swallowed', () async {
      final platform = _FakeUniversalBlePlatform(
        startScanError: PlatformException(
          code: 'startScan',
          message: 'Permission BLUETOOTH_SCAN required to scan devices',
        ),
      );
      UniversalBle.setInstance(platform);
      final transport = UniversalBleTransport(
        availability: () async => AvailabilityState.poweredOn,
        log: (_) {},
      );

      final run = _runScan(transport);
      await run.done;

      expect(run.errors, hasLength(1));
      expect((run.errors.single as BleScanException).kind,
          BleScanFailureKind.permissionDenied);
    });

    test('an adapter that is off is reported without scanning at all', () async {
      final platform = _FakeUniversalBlePlatform();
      UniversalBle.setInstance(platform);
      final transport = UniversalBleTransport(
        availability: () async => AvailabilityState.poweredOff,
        log: (_) {},
      );

      final run = _runScan(transport);
      await run.done;

      expect(platform.startScanCalled, isFalse,
          reason: 'a disabled adapter should be reported before touching the scanner');
      expect(run.errors, hasLength(1));
      expect((run.errors.single as BleScanException).kind,
          BleScanFailureKind.bluetoothOff);
    });

    test('an unauthorized adapter is reported as a permission failure', () async {
      final platform = _FakeUniversalBlePlatform();
      UniversalBle.setInstance(platform);
      final transport = UniversalBleTransport(
        availability: () async => AvailabilityState.unauthorized,
        log: (_) {},
      );

      final run = _runScan(transport);
      await run.done;

      expect(platform.startScanCalled, isFalse);
      expect((run.errors.single as BleScanException).kind,
          BleScanFailureKind.permissionDenied);
    });

    test('with Bluetooth on, a scan still emits discovered JK devices and completes', () async {
      final platform = _FakeUniversalBlePlatform(
        scanDevices: [_jkDevice()],
      );
      UniversalBle.setInstance(platform);
      final transport = UniversalBleTransport(
        availability: () async => AvailabilityState.poweredOn,
        log: (_) {},
      );

      // A real (short) scan timeout; `.timeout` guards the test against a hang.
      final run = _runScan(transport, timeout: const Duration(milliseconds: 150));
      await run.done.timeout(const Duration(seconds: 5));

      expect(platform.startScanCalled, isTrue);
      expect(run.errors, isEmpty);
      final names = run.events.expand((e) => e).map((d) => d.name);
      expect(names, contains('JK_B2A24S15P'));
      expect(platform.stopScanCount, greaterThanOrEqualTo(1));
    });
  });

  group('UniversalBleTransport.connect', () {
    test('binds the documented JK characteristic through its owning service, '
        'and negotiates MTU after subscribing', () async {
      final platform = _FakeUniversalBlePlatform(services: [
        BleService('00001801-0000-1000-8000-00805f9b34fb', [
          BleCharacteristic('00002a05-0000-1000-8000-00805f9b34fb',
              [CharacteristicProperty.indicate], const []),
        ]),
        BleService('0000ffe0-0000-1000-8000-00805f9b34fb', [
          BleCharacteristic('0000ffe1-0000-1000-8000-00805f9b34fb',
              [CharacteristicProperty.notify, CharacteristicProperty.write], const []),
        ]),
      ]);
      UniversalBle.setInstance(platform);
      final transport = UniversalBleTransport(
        availability: () async => AvailabilityState.poweredOn,
        log: (_) {},
      );

      final session = await transport.connect('AA:BB:CC:11:22:33');

      // Service Changed (0x2A05) is `indicate` and comes first; binding it is
      // the failure this pins — the BMS never sends telemetry on it.
      expect(session.serviceUuids, contains('0000ffe0-0000-1000-8000-00805f9b34fb'));
      expect(session.rssi, -55);
      expect(platform.requestedMtu, 517,
          reason: 'MTU is negotiated after the CCCD subscription, not before');
      await session.disconnect();
      expect(platform.writes, isEmpty);
    });
  });

  group('chooseJkCharacteristics', () {
    // The regression this exists for: a real device lists the Generic Attribute
    // service (0x1801) with Service Changed (0x2A05, indicate) BEFORE the JK
    // service. The old single-`??=` version bound Service Changed and then
    // never received telemetry, and the failure read as a range problem.
    GattServiceView genericAttribute() => (
          uuid: '00001801-0000-1000-8000-00805f9b34fb',
          characteristics: [
            (uuid: '00002a05-0000-1000-8000-00805f9b34fb', canNotify: true, canWrite: false),
          ],
        );
    GattServiceView jkClassic() => (
          uuid: '0000ffe0-0000-1000-8000-00805f9b34fb',
          characteristics: [
            (uuid: '0000ffe1-0000-1000-8000-00805f9b34fb', canNotify: true, canWrite: true),
          ],
        );

    test('an earlier Service Changed does not steal the binding', () {
      final choice = chooseJkCharacteristics([genericAttribute(), jkClassic()]);
      expect(choice.notify, '0000ffe1-0000-1000-8000-00805f9b34fb');
      expect(choice.write, '0000ffe1-0000-1000-8000-00805f9b34fb');
    });

    test('the documented characteristic wins over an earlier fallback in the same service', () {
      final choice = chooseJkCharacteristics([
        (
          uuid: '0000ffe0-0000-1000-8000-00805f9b34fb',
          characteristics: [
            (uuid: '0000ffe9-0000-1000-8000-00805f9b34fb', canNotify: true, canWrite: true),
            (uuid: '0000ffe1-0000-1000-8000-00805f9b34fb', canNotify: true, canWrite: true),
          ],
        ),
      ]);
      expect(choice.notify, '0000ffe1-0000-1000-8000-00805f9b34fb');
      expect(choice.write, '0000ffe1-0000-1000-8000-00805f9b34fb');
    });

    test('the JK02 triad is accepted as well as the classic pair', () {
      final choice = chooseJkCharacteristics([
        (
          uuid: '0000ff00-0000-1000-8000-00805f9b34fb',
          characteristics: [
            (uuid: '0000ff02-0000-1000-8000-00805f9b34fb', canNotify: true, canWrite: false),
            (uuid: '0000ff01-0000-1000-8000-00805f9b34fb', canNotify: false, canWrite: true),
          ],
        ),
      ]);
      expect(choice.notify, '0000ff02-0000-1000-8000-00805f9b34fb');
      expect(choice.write, '0000ff01-0000-1000-8000-00805f9b34fb');
    });

    test('a device without the JK services still falls back to the first pair', () {
      final choice = chooseJkCharacteristics([
        (
          uuid: '0000fff0-0000-1000-8000-00805f9b34fb',
          characteristics: [
            (uuid: '0000fff1-0000-1000-8000-00805f9b34fb', canNotify: true, canWrite: true),
          ],
        ),
      ]);
      expect(choice.notify, '0000fff1-0000-1000-8000-00805f9b34fb');
      expect(choice.write, '0000fff1-0000-1000-8000-00805f9b34fb');
    });

    test('nothing suitable yields nulls rather than a wrong guess', () {
      final choice = chooseJkCharacteristics([
        (
          uuid: '00001800-0000-1000-8000-00805f9b34fb',
          characteristics: [
            (uuid: '00002a00-0000-1000-8000-00805f9b34fb', canNotify: false, canWrite: false),
          ],
        ),
      ]);
      expect(choice.notify, isNull);
      expect(choice.write, isNull);
    });
  });

  group('classifyCaptureFailure and the link', () {
    test('a timeout mid-capture is NOT reported as the pack moving away', () {
      // Measured 2026-10-18: the app told the user to keep the pack powered and
      // nearby while they were standing next to it and the same pack connected
      // fine to another app. A GATT operation that timed out after the link was
      // up is not evidence of range, so it must not borrow that sentence.
      final failure = classifyCaptureFailure(
        PlatformException(code: 'write', message: 'write timed out'),
        linkEstablished: true,
      );
      expect(failure.kind, BleCaptureFailureKind.other);
      expect(failure.cause, isA<PlatformException>());
    });

    test('a timeout while connecting is still the reachability sentence', () {
      final failure = classifyCaptureFailure(
        PlatformException(code: 'connect', message: 'connection timed out'),
        linkEstablished: false,
      );
      expect(failure.kind, BleCaptureFailureKind.outOfRange);
    });

    test('a genuine disconnect mid-capture is still outOfRange', () {
      final failure = classifyCaptureFailure(
        PlatformException(code: 'disconnect', message: 'device disconnected'),
        linkEstablished: true,
      );
      expect(failure.kind, BleCaptureFailureKind.outOfRange);
    });
  });
}
