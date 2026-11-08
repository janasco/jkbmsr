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
  FakeBleTransport({BleScanResult? device, this.logbookDelay = Duration.zero})
      : device = device ??
            const BleScanResult(
              id: 'AA:BB:CC:11:22:33',
              name: 'JK_B2A24S15P',
              rssi: -63,
              serviceUuids: [_jkService],
            );

  final BleScanResult device;

  /// How long after the 0xA1 request the fake device answers with 0x05.
  /// Real hardware answers behind the telemetry stream, not inside the write
  /// call — a fake that answers synchronously is why a 50 ms wait passed tests
  /// and failed on every real pack.
  final Duration logbookDelay;

  FakeBleSession? lastSession;

  @override
  Future<bool> isSupported() async => true;

  @override
  Stream<List<BleScanResult>> scan({Duration timeout = const Duration(seconds: 12)}) =>
      Stream.value([device]);

  @override
  Future<BleSession> connect(String deviceId) async {
    final session = FakeBleSession(logbookDelay: logbookDelay);
    lastSession = session;
    return session;
  }
}

class FakeBleSession implements BleSession {
  FakeBleSession({this.logbookDelay = Duration.zero});

  final Duration logbookDelay;
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
        if (logbookDelay == Duration.zero) {
          _emit(logbookHex);
        } else {
          Future<void>.delayed(logbookDelay, () {
            // The capture may have finished and disconnected by then.
            if (!_controller.isClosed) _emit(logbookHex);
          });
        }
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
    /// Drains every frame a sequence of fragments completes.
    List<List<int>> drain(List<List<int>> fragments) {
      final accumulator = Jk02FrameAccumulator();
      final frames = <List<int>>[];
      for (final fragment in fragments) {
        frames.addAll(accumulator.add(fragment));
      }
      return frames;
    }

    test('reassembles a 300-byte frame from 20-byte fragments', () {
      final frames = drain(chunk(bytesFromHex(devInfo24sHex)));

      expect(frames, hasLength(1));
      expect(frames.single.length, 300);
      expect(frames.single[4], 0x03);
    });

    test('a corrupted CRC is rejected, never returned as a frame', () {
      final bytes = bytesFromHex(devInfo24sHex);
      bytes[299] ^= 0xFF;

      expect(drain(chunk(bytes)), isEmpty);
    });

    test('a truncated leading frame is discarded once the next magic arrives', () {
      // A partial frame first, then a clean one — and exactly one frame comes
      // out, not a window stitched across the boundary.
      final frames = drain([
        ...chunk(bytesFromHex(cellInfo24sHex).sublist(0, 50)),
        ...chunk(bytesFromHex(devInfo24sHex)),
      ]);

      expect(frames, hasLength(1));
      expect(frames.single[4], 0x03);
    });

    test('resyncs when a notification begins mid-frame', () {
      // A dropped notification leaves the stream 37 bytes into a frame, so the
      // following frame's magic does not land on a notification boundary. The old
      // accumulator only resynced when a *fragment* began with the magic, so it
      // stayed misaligned and discarded the frame that followed.
      final bytes = bytesFromHex(devInfo24sHex);

      final frames = drain(chunk([...bytes.sublist(37), ...bytes]));

      expect(frames, hasLength(1));
      expect(frames.single[4], 0x03);
    });

    test('returns BOTH frames when one notification carries two', () {
      // The case that lost the logbook: the 0x05 response shares a notification
      // with the tail of a cell-info frame. The old version returned one frame
      // per notification and kept at most a frame's worth of bytes.
      final accumulator = Jk02FrameAccumulator();
      final frames = accumulator.add([
        ...bytesFromHex(cellInfo24sHex),
        ...bytesFromHex(logbookHex),
      ]);

      expect(frames.map((f) => f[4]).toList(), [0x02, 0x05]);
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

    test('waits for the logbook frame instead of a fixed 50 ms', () async {
      // Real hardware answers 0xA1 with a 300-byte frame that arrives after the
      // write returns, behind the telemetry stream. The old code waited one poll
      // tick (50 ms) and disconnected, which is why no contribution had ever
      // carried a logbook entry.
      final transport = FakeBleTransport(logbookDelay: const Duration(milliseconds: 400));
      final service = CaptureService(transport: transport);

      final outcome = await service.capture(
        transport.device,
        duration: const Duration(milliseconds: 80),
        handshakeTimeout: const Duration(milliseconds: 500),
        app: const AppProvenance(version: '0.1.0+1', platform: 'android', osVersion: '34'),
      );

      expect(outcome.success, isTrue, reason: outcome.error);
      expect(outcome.contribution!.logbook, isNotNull);
      expect(outcome.contribution!.logbook!.entries.length, 4);
      expect(
        outcome.contribution!.rawFrames.map((f) => f.frameType),
        contains('logbook'),
      );
    });

    test('a device that ignores the logbook request does not hang the capture', () async {
      // Best-effort means bounded: no 0x05 ever arrives, the capture still
      // succeeds and simply carries no logbook.
      final transport = FakeBleTransport(logbookDelay: const Duration(minutes: 5));
      final logs = <String>[];
      final service = CaptureService(transport: transport, log: logs.add);
      final watch = Stopwatch()..start();

      final outcome = await service.capture(
        transport.device,
        duration: const Duration(milliseconds: 80),
        handshakeTimeout: const Duration(milliseconds: 500),
        logbookTimeout: const Duration(milliseconds: 200),
        app: const AppProvenance(version: '0.1.0+1', platform: 'android', osVersion: '34'),
      );
      watch.stop();

      expect(outcome.success, isTrue, reason: outcome.error);
      expect(outcome.contribution!.logbook, isNull);
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
      // The absence is recorded, so a later capture can tell "the device
      // ignored it" from "we never asked".
      expect(logs.join('\n'), contains('no logbook frame within 200ms'));
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
