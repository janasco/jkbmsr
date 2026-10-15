import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_contributor/l10n/strings.dart';
import 'package:jkbmsr_contributor/models/contribution.dart';
import 'package:jkbmsr_contributor/services/ble_transport.dart';
import 'package:jkbmsr_contributor/services/capture_service.dart';

import '../support/jk02_fixtures.dart';

const _jkService = '0000ffe0-0000-1000-8000-00805f9b34fb';

/// A fake transport that answers each JK02 command with the captured fixture
/// frames, split into ~20-byte notifications exactly as real hardware sends
/// them. No radio, no plugin.
class FakeBleTransport implements BleTransport {
  FakeBleTransport({BleScanResult? device})
      : device = device ??
            const BleScanResult(
              id: 'AA:BB:CC:11:22:33',
              name: 'JK_B2A24S15P',
              rssi: -63,
              serviceUuids: [_jkService],
            );

  final BleScanResult device;
  FakeBleSession? lastSession;

  @override
  Future<bool> isSupported() async => true;

  @override
  Stream<List<BleScanResult>> scan({Duration timeout = const Duration(seconds: 12)}) =>
      Stream.value([device]);

  @override
  Future<BleSession> connect(String deviceId) async {
    final session = FakeBleSession();
    lastSession = session;
    return session;
  }
}

class FakeBleSession implements BleSession {
  final StreamController<List<int>> _controller = StreamController<List<int>>.broadcast();
  bool disconnected = false;

  @override
  String get deviceName => 'JK_B2A24S15P';

  @override
  int get rssi => -63;

  @override
  List<String> get serviceUuids => const [_jkService];

  @override
  Stream<List<int>> get notifications => _controller.stream;

  @override
  Future<void> write(List<int> data) async {
    final register = data.length > 4 ? data[4] : -1;
    switch (register) {
      case 0x97:
        _emit(devInfo24sHex);
        break;
      case 0x96:
        _emit(cellInfo24sHex);
        break;
      case 0xA1:
        _emit(logbookHex);
        break;
    }
  }

  void _emit(String hex) {
    for (final fragment in chunk(bytesFromHex(hex))) {
      _controller.add(fragment);
    }
  }

  @override
  Future<void> disconnect() async {
    disconnected = true;
    await _controller.close();
  }
}

void main() {
  group('Jk02FrameAccumulator', () {
    test('reassembles a 300-byte frame from 20-byte fragments', () {
      final accumulator = Jk02FrameAccumulator();
      final chunks = chunk(bytesFromHex(devInfo24sHex));

      List<int>? frame;
      for (final c in chunks) {
        frame = accumulator.add(c);
      }
      expect(frame, isNotNull);
      expect(frame!.length, 300);
      expect(frame[4], 0x03);
    });

    test('a corrupted CRC is rejected, never returned as a frame', () {
      final accumulator = Jk02FrameAccumulator();
      final bytes = bytesFromHex(devInfo24sHex);
      bytes[299] ^= 0xFF;
      List<int>? frame;
      for (final c in chunk(bytes)) {
        frame = accumulator.add(c);
      }
      expect(frame, isNull);
    });

    test('a new magic fragment resyncs and drops the partial frame', () {
      final accumulator = Jk02FrameAccumulator();
      // A truncated leading frame, then a clean one.
      accumulator.add(bytesFromHex(cellInfo24sHex).sublist(0, 50));
      final bytes = bytesFromHex(devInfo24sHex);
      List<int>? frame;
      for (final c in chunk(bytes)) {
        frame = accumulator.add(c);
      }
      expect(frame, isNotNull);
      expect(frame![4], 0x03);
    });
  });

  group('Jk02CaptureSession', () {
    test('decodes device info and a cell-info sample from fragments', () {
      final session = Jk02CaptureSession();
      session.start();
      for (final c in chunk(bytesFromHex(devInfo24sHex))) {
        session.addFragment(c);
      }
      for (final c in chunk(bytesFromHex(cellInfo24sHex))) {
        session.addFragment(c);
      }

      expect(session.deviceInfo, isNotNull);
      expect(session.deviceInfo!.modelName, 'JK-B2A24S15P');
      expect(session.is32s, isFalse);
      expect(session.statuses.length, 1);
      expect(session.statuses.single.cells.length, 16);
      expect(session.rawFrames.length, 2);
      expect(session.rawFrames.map((f) => f.frameType), ['deviceInfo', 'cellInfo']);
    });

    test('a cell-info frame before device-info is stashed, not guessed', () {
      final session = Jk02CaptureSession();
      session.start();
      for (final c in chunk(bytesFromHex(cellInfo24sHex))) {
        session.addFragment(c);
      }
      expect(session.statuses, isEmpty); // layout unknown yet

      for (final c in chunk(bytesFromHex(devInfo24sHex))) {
        session.addFragment(c);
      }
      expect(session.statuses.length, 1); // parsed once layout is known
    });
  });

  group('CaptureService.capture', () {
    test('builds an anonymised contribution from a fake radio', () async {
      final transport = FakeBleTransport();
      final logs = <String>[];
      final service = CaptureService(transport: transport, log: logs.add);

      final outcome = await service.capture(
        transport.device,
        duration: const Duration(milliseconds: 80),
        handshakeTimeout: const Duration(milliseconds: 500),
        app: const AppProvenance(version: '0.1.0+1', platform: 'android', osVersion: '34'),
      );

      expect(outcome.success, isTrue, reason: outcome.error);
      // A success carries no failure kind and logs nothing.
      expect(outcome.failureKind, isNull);
      expect(logs, isEmpty);
      final c = outcome.contribution!;
      expect(c.bms.modelName, 'JK-B2A24S15P');
      expect(c.bms.hardwareVersion, '10.XW');
      expect(c.bms.layout, 'JK02_24S');
      expect(c.bms.cellCountReported, 16);
      expect(c.samples.length, 1);
      expect(c.samples.single.voltageV, closeTo(53.251, 0.01));
      expect(c.samples.single.socPct, 84);
      expect(c.rawFrames.length, greaterThanOrEqualTo(2));
      expect(c.logbook!.entries.length, 4);
      // Anonymisation defaults hold end to end.
      expect(c.contributionId, startsWith('c_'));
      expect(c.bms.serialHash, isNull);
      expect(c.redaction.serialNumber, 'withheld');
      expect(c.advertisement.addressMasked, 'AA:BB:CC:00:00:00');
      expect(c.advertisement.namePattern, 'JK_*');
      expect(c.isWithinSizeCap(), isTrue);

      expect(transport.lastSession!.disconnected, isTrue);
    });

    test('reports failure when the BMS never answers device-info', () async {
      final transport = _SilentTransport();
      final service = CaptureService(transport: transport);

      final outcome = await service.capture(
        transport.device,
        handshakeTimeout: const Duration(milliseconds: 80),
        duration: const Duration(milliseconds: 20),
        app: const AppProvenance(version: '0.1.0+1', platform: 'android', osVersion: '34'),
      );

      expect(outcome.success, isFalse);
      expect(outcome.error, contains('device-info'));
    });
  });

  group('CaptureService.capture failure translation', () {
    Future<CaptureOutcome> run(_ThrowingTransport transport, List<String> logs) =>
        CaptureService(transport: transport, log: logs.add).capture(
          transport.device,
          duration: const Duration(milliseconds: 20),
          handshakeTimeout: const Duration(milliseconds: 200),
          app: const AppProvenance(version: '0.1.0+1', platform: 'android', osVersion: '34'),
        );

    test('Bluetooth switched off mid-capture shows the plain sentence and logs the cause',
        () async {
      // flutter_blue_plus reports a disabled adapter as a raw exception. It
      // arrives *after* a successful scan — mid-session — and used to surface as
      // `Capture failed: PlatformException(...)`.
      final logs = <String>[];
      final outcome = await run(
        _ThrowingTransport(
          error: PlatformException(
            code: 'connect',
            message: 'Bluetooth must be turned on',
          ),
        ),
        logs,
      );

      expect(outcome.success, isFalse);
      expect(outcome.failureKind, BleCaptureFailureKind.bluetoothOff);
      expect(
        outcome.error,
        CaptureStrings.captureFailure(BleCaptureFailureKind.bluetoothOff),
      );
      expect(outcome.error, isNot(contains('PlatformException')));
      expect(outcome.error, isNot(contains('Bluetooth must be turned on')));
      expect(outcome.error, isNot(contains('Capture failed')));
      // The raw reason is kept for the logs, never shown.
      expect(logs.join('\n'), contains('Bluetooth must be turned on'));
    });

    test('the pack going out of range is a distinct, actionable condition', () async {
      final logs = <String>[];
      final outcome = await run(
        _ThrowingTransport(
          error: PlatformException(
            code: 'connect',
            message: 'connection failed: device is out of range',
          ),
        ),
        logs,
      );

      expect(outcome.failureKind, BleCaptureFailureKind.outOfRange);
      expect(
        outcome.error,
        CaptureStrings.captureFailure(BleCaptureFailureKind.outOfRange),
      );
      expect(outcome.error, isNot(contains('PlatformException')));
      expect(logs.join('\n'), contains('out of range'));
    });

    test('a generic GATT error is not mislabelled as out-of-range', () async {
      final logs = <String>[];
      final outcome = await run(
        _ThrowingTransport(
          error: PlatformException(
            code: 'gatt',
            message: 'GATT error: could not write characteristic',
          ),
        ),
        logs,
      );

      expect(outcome.failureKind, BleCaptureFailureKind.other);
      expect(
        outcome.error,
        CaptureStrings.captureFailure(BleCaptureFailureKind.other),
      );
      expect(outcome.error, isNot(contains('GATT error')));
      // Still recorded for support, just not shown.
      expect(logs.join('\n'), contains('GATT error'));
    });
  });
}

/// A transport whose session never emits anything.
class _SilentTransport implements BleTransport {
  final BleScanResult device = const BleScanResult(
    id: 'AA:BB:CC:11:22:33',
    name: 'JK_B2A24S15P',
    rssi: -63,
  );

  @override
  Future<bool> isSupported() async => true;

  @override
  Stream<List<BleScanResult>> scan({Duration timeout = const Duration(seconds: 12)}) =>
      Stream.value([device]);

  @override
  Future<BleSession> connect(String deviceId) async => _SilentSession();
}

class _SilentSession implements BleSession {
  final StreamController<List<int>> _controller = StreamController<List<int>>.broadcast();

  @override
  String get deviceName => 'silent';

  @override
  int get rssi => -63;

  @override
  List<String> get serviceUuids => const [];

  @override
  Stream<List<int>> get notifications => _controller.stream;

  @override
  Future<void> write(List<int> data) async {}

  @override
  Future<void> disconnect() async {
    await _controller.close();
  }
}

/// A transport that presents a normal device-info handshake, then fails the
/// write that follows — the shape of every mid-capture failure (adapter off,
/// out of range, GATT error), which happens *after* a successful scan.
class _ThrowingTransport implements BleTransport {
  _ThrowingTransport({required this.error});

  final Object error;

  final BleScanResult device = const BleScanResult(
    id: 'AA:BB:CC:11:22:33',
    name: 'JK_B2A24S15P',
    rssi: -63,
  );

  @override
  Future<bool> isSupported() async => true;

  @override
  Stream<List<BleScanResult>> scan({Duration timeout = const Duration(seconds: 12)}) =>
      Stream.value([device]);

  @override
  Future<BleSession> connect(String deviceId) async => _ThrowingSession(error);
}

class _ThrowingSession implements BleSession {
  _ThrowingSession(this.error);

  final Object error;
  final StreamController<List<int>> _controller = StreamController<List<int>>.broadcast();

  @override
  String get deviceName => 'JK_B2A24S15P';

  @override
  int get rssi => -63;

  @override
  List<String> get serviceUuids => const [];

  @override
  Stream<List<int>> get notifications => _controller.stream;

  @override
  Future<void> write(List<int> data) async {
    final register = data.length > 4 ? data[4] : -1;
    if (register == 0x97) {
      // Answer the device-info request so the handshake completes…
      for (final fragment in chunk(bytesFromHex(devInfo24sHex))) {
        _controller.add(fragment);
      }
      return;
    }
    // …then fail on the next write, as a dropped link does.
    throw error;
  }

  @override
  Future<void> disconnect() async {
    await _controller.close();
  }
}
