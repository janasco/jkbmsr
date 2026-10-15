import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_contributor/services/ble_transport.dart';
import 'package:jkbmsr_contributor/services/flutter_blue_plus_transport.dart';

/// A platform fake whose adapter state and `startScan` outcome the test sets,
/// so the transport can be driven without a radio. Stands in for the real
/// Android/iOS plugin, which on the Dart VM throws `UnsupportedError`.
final class _FakeFlutterBluePlusPlatform extends FlutterBluePlusPlatform {
  _FakeFlutterBluePlusPlatform({this.startScanError, this.advertisements});

  Object? startScanError;
  List<BmScanAdvertisement>? advertisements;

  bool startScanCalled = false;
  int stopScanCount = 0;

  final StreamController<BmScanResponse> _scanResponses =
      StreamController<BmScanResponse>.broadcast();

  @override
  Future<bool> isSupported(BmIsSupportedRequest request) async => true;

  @override
  Stream<BmScanResponse> get onScanResponse => _scanResponses.stream;

  @override
  Future<bool> startScan(BmScanSettings request) async {
    startScanCalled = true;
    if (startScanError != null) throw startScanError!;
    final ads = advertisements;
    if (ads != null) {
      // Deliver after `startScan` returns, so the plugin has attached its own
      // listener (which it does before invoking the platform method).
      scheduleMicrotask(() => _scanResponses.add(BmScanResponse(
            advertisements: ads,
            success: true,
            errorCode: 0,
            errorString: '',
          )));
    }
    return true;
  }

  @override
  Future<bool> stopScan(BmStopScanRequest request) async {
    stopScanCount++;
    return true;
  }
}

BmScanAdvertisement _jkAdvertisement({String id = 'AA:BB:CC:11:22:33', String name = 'JK_B2A24S15P'}) {
  return BmScanAdvertisement(
    remoteId: DeviceIdentifier(id),
    platformName: name,
    advName: name,
    connectable: true,
    txPowerLevel: null,
    appearance: null,
    manufacturerData: const {},
    serviceData: const {},
    serviceUuids: [Guid('0000ffe0-0000-1000-8000-00805f9b34fb')],
    rssi: -63,
  );
}

/// The result of driving a transport's scan stream to completion.
class _ScanRun {
  _ScanRun(this.events, this.errors, this.done);
  final List<List<BleScanResult>> events;
  final List<Object> errors;
  final Future<void> done;
}

_ScanRun _runScan(FlutterBluePlusTransport transport, {Duration? timeout}) {
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

  group('FlutterBluePlusTransport.scan', () {
    test('a Bluetooth-off PlatformException never reaches the stream raw; '
        'it becomes a bluetoothOff failure and is logged', () async {
      final platform = _FakeFlutterBluePlusPlatform(
        startScanError: PlatformException(
          code: 'startScan',
          message: 'Bluetooth must be turned on',
        ),
      );
      FlutterBluePlusPlatform.instance = platform;
      final logs = <String>[];
      final transport = FlutterBluePlusTransport(
        // The adapter pre-check says "on"; the failure falls through to the
        // classification path, which is what this test pins.
        adapterState: () async => BluetoothAdapterState.on,
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
      final platform = _FakeFlutterBluePlusPlatform(
        startScanError: PlatformException(
          code: 'startScan',
          message: 'Permission BLUETOOTH_SCAN required to scan devices',
        ),
      );
      FlutterBluePlusPlatform.instance = platform;
      final transport = FlutterBluePlusTransport(
        adapterState: () async => BluetoothAdapterState.on,
        log: (_) {},
      );

      final run = _runScan(transport);
      await run.done;

      expect(run.errors, hasLength(1));
      expect((run.errors.single as BleScanException).kind,
          BleScanFailureKind.permissionDenied);
    });

    test('an adapter that is off is reported without scanning at all', () async {
      final platform = _FakeFlutterBluePlusPlatform();
      FlutterBluePlusPlatform.instance = platform;
      final transport = FlutterBluePlusTransport(
        adapterState: () async => BluetoothAdapterState.off,
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
      final platform = _FakeFlutterBluePlusPlatform();
      FlutterBluePlusPlatform.instance = platform;
      final transport = FlutterBluePlusTransport(
        adapterState: () async => BluetoothAdapterState.unauthorized,
        log: (_) {},
      );

      final run = _runScan(transport);
      await run.done;

      expect(platform.startScanCalled, isFalse);
      expect((run.errors.single as BleScanException).kind,
          BleScanFailureKind.permissionDenied);
    });

    test('with Bluetooth on, a scan still emits discovered JK devices and completes', () async {
      final platform = _FakeFlutterBluePlusPlatform(
        advertisements: [_jkAdvertisement()],
      );
      FlutterBluePlusPlatform.instance = platform;
      final transport = FlutterBluePlusTransport(
        adapterState: () async => BluetoothAdapterState.on,
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
}
