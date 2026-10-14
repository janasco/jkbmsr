import 'dart:async';

import 'package:bms_core/bms_core.dart';

import '../models/contribution.dart';
import 'ble_transport.dart';

/// Accumulates JK02 notification fragments into complete 300-byte frames.
///
/// Real JK02 hardware sends a 300-byte response across many ~20-byte BLE
/// notifications, so a fragment is never a frame. A fragment that begins with
/// the `55 AA EB 90` magic starts a new frame (any partial previous frame is
/// dropped); a frame is emitted only once 300 bytes have accumulated *and* the
/// trailing check-sum validates. This is the same reassembly rule `apps/ble`
/// applies, factored out so it is unit-testable without a radio.
class Jk02FrameAccumulator {
  static const int frameSize = 300;

  final List<int> _buffer = [];

  void reset() => _buffer.clear();

  /// Feeds one fragment; returns a complete, CRC-valid frame or null.
  List<int>? add(List<int> fragment) {
    if (fragment.length >= 4 &&
        fragment[0] == 0x55 &&
        fragment[1] == 0xAA &&
        fragment[2] == 0xEB &&
        fragment[3] == 0x90) {
      _buffer.clear();
    }
    _buffer.addAll(fragment);

    // Only ever hold at most one frame's worth; a stream that never syncs on
    // the magic must not grow without bound.
    if (_buffer.length > frameSize) {
      final frame = _buffer.sublist(0, frameSize);
      _buffer.removeRange(0, frameSize);
      if (BmsProtocolHelper.isCompleteJk02Frame(frame)) return frame;
      return null;
    }

    if (_buffer.length == frameSize &&
        BmsProtocolHelper.isCompleteJk02Frame(_buffer)) {
      final frame = List<int>.of(_buffer);
      _buffer.clear();
      return frame;
    }
    return null;
  }
}

/// Live progress of a capture, for the status line.
class CaptureProgress {
  final String status;
  final int fragmentCount;
  final int frameCount;
  final int sampleCount;

  const CaptureProgress({
    required this.status,
    required this.fragmentCount,
    required this.frameCount,
    required this.sampleCount,
  });
}

/// The result of a capture attempt.
class CaptureOutcome {
  final Contribution? contribution;
  final Jk02CaptureSession? session;
  final String? error;

  const CaptureOutcome._({this.contribution, this.session, this.error});

  bool get success => contribution != null;

  factory CaptureOutcome.success(Contribution contribution, Jk02CaptureSession session) =>
      CaptureOutcome._(contribution: contribution, session: session);

  factory CaptureOutcome.failure(String error) => CaptureOutcome._(error: error);
}

/// Decodes complete JK02 frames into the pieces a donation carries.
///
/// Pure: it has no radio, no timers and no I/O — feed it fragments and read
/// the accumulated device info, samples, settings, logbook and raw frames.
class Jk02CaptureSession {
  final Jk02FrameAccumulator _accumulator = Jk02FrameAccumulator();
  final Stopwatch _stopwatch = Stopwatch();

  BmsModelInfo? deviceInfo;
  bool is32s = false;

  final List<BmsStatus> statuses = [];
  final List<int> statusOffsetsMs = [];

  Map<String, double>? settingsValues;
  final List<LogbookCaptureEntry> logbookEntries = [];

  final List<RawFrame> rawFrames = [];

  int fragmentCount = 0;
  int frameCount = 0;

  List<int>? _pendingCellInfo;
  int _pendingCellInfoOffsetMs = 0;

  void start() => _stopwatch.start();

  int get elapsedMs => _stopwatch.elapsedMilliseconds;

  /// Feeds a notification fragment.
  void addFragment(List<int> fragment) {
    fragmentCount++;
    final frame = _accumulator.add(fragment);
    if (frame == null) return;
    frameCount++;

    final offsetMs = elapsedMs;
    switch (frame[4]) {
      case 0x03:
        deviceInfo = BmsProtocolHelper.parseJk02DeviceInfoFrame(frame);
        is32s = BmsProtocolHelper.parseJk02DeviceInfoIs32s(frame) ?? false;
        rawFrames.add(_raw(frame, offsetMs, 'deviceInfo'));
        final pending = _pendingCellInfo;
        if (pending != null) {
          _pendingCellInfo = null;
          _decodeCellInfo(pending, _pendingCellInfoOffsetMs);
        }
        break;
      case 0x02:
        rawFrames.add(_raw(frame, offsetMs, 'cellInfo'));
        if (deviceInfo == null) {
          // Layout unknown until device-info arrives; stash rather than guess.
          _pendingCellInfo = frame;
          _pendingCellInfoOffsetMs = offsetMs;
        } else {
          _decodeCellInfo(frame, offsetMs);
        }
        break;
      case 0x01:
        final raw = BmsProtocolHelper.parseJk02SettingsFrame(frame);
        if (raw != null) {
          settingsValues = _settingsFromRaw(raw);
          rawFrames.add(_raw(frame, offsetMs, 'settings'));
        }
        break;
      case 0x05:
        final logbook = BmsProtocolHelper.parseJk02LogbookFrame(frame);
        if (logbook != null) {
          logbookEntries
            ..clear()
            ..addAll(logbook.entries
                .map((e) => LogbookCaptureEntry(seconds: e.seconds, code: e.code)));
          rawFrames.add(_raw(frame, offsetMs, 'logbook'));
        }
        break;
      default:
        rawFrames.add(_raw(frame, offsetMs, 'unknown'));
    }
  }

  void _decodeCellInfo(List<int> frame, int offsetMs) {
    final status = BmsProtocolHelper.parseJk02CellInfoFrame(frame, is32s: is32s);
    if (status == null) return;
    statuses.add(status);
    statusOffsetsMs.add(offsetMs);
  }

  Map<String, double> _settingsFromRaw(Map<int, int> raw) {
    final schema = BmsParameterSchema.forBrand(BmsBrand.jkbms) ?? const [];
    final values = <String, double>{};
    for (final p in schema) {
      final offset = p.jkFrameOffset;
      if (offset == null) continue;
      final r = raw[offset];
      if (r == null) continue;
      values[p.id] = r * p.jkRawFactor;
    }
    return values;
  }

  RawFrame _raw(List<int> frame, int offsetMs, String type) =>
      RawFrame(dir: 'rx', tOffsetMs: offsetMs, hex: _hex(frame), frameType: type);

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// A capture controller the UI depends on, so the screen can be driven by a
/// fake in widget tests while [CaptureService] is the real implementation.
abstract interface class CaptureController {
  Future<bool> isSupported();

  Stream<List<BleScanResult>> scan({Duration timeout});

  Future<CaptureOutcome> capture(
    BleScanResult device, {
    Duration duration,
    Duration handshakeTimeout,
    bool includeSerial,
    required AppProvenance app,
    bool Function()? isCancelled,
    void Function(CaptureProgress progress)? onProgress,
  });
}

/// Orchestrates a capture over a [BleTransport]: scan, connect, handshake,
/// collect samples for a bounded duration, then build the versioned payload.
///
/// The transport is injected, so the whole flow except the radio calls is
/// unit-tested with a fake.
class CaptureService implements CaptureController {
  CaptureService({required BleTransport transport}) : _transport = transport;

  final BleTransport _transport;

  /// How long to wait for the device-info (0x03) handshake before giving up.
  static const Duration defaultHandshakeTimeout = Duration(seconds: 5);

  /// The default capture window offered by the UI.
  static const Duration defaultDuration = Duration(seconds: 30);

  static const Duration _pollInterval = Duration(milliseconds: 50);

  @override
  Future<bool> isSupported() => _transport.isSupported();

  @override
  Stream<List<BleScanResult>> scan({
    Duration timeout = const Duration(seconds: 12),
  }) =>
      _transport.scan(timeout: timeout);

  /// Connects to [device], reads the device-info and cell-info frames, and
  /// returns a [Contribution] built with every anonymisation default applied.
  ///
  /// [isCancelled] lets the UI stop collection early; the payload is still
  /// built from whatever was captured (with an honest zero-sample failure when
  /// nothing parsed).
  @override
  Future<CaptureOutcome> capture(
    BleScanResult device, {
    Duration duration = defaultDuration,
    Duration handshakeTimeout = defaultHandshakeTimeout,
    bool includeSerial = false,
    required AppProvenance app,
    bool Function()? isCancelled,
    void Function(CaptureProgress progress)? onProgress,
  }) async {
    final session = Jk02CaptureSession();
    BleSession? ble;
    StreamSubscription<List<int>>? subscription;
    try {
      ble = await _transport.connect(device.id);
      subscription = ble.notifications.listen(session.addFragment);
      session.start();

      onProgress?.call(_progress(session, 'Reading device info…'));

      // JK02 order (verified against real hardware): request device info
      // (0x97) first, then cell info (0x96). The device-info frame also tells
      // us whether the pack uses the 24- or 32-cell register layout.
      await ble.write(
        BmsProtocolHelper.buildJk02Command(BmsProtocolHelper.jk02CommandDeviceInfo),
      );

      final handshakeDeadline = DateTime.now().add(handshakeTimeout);
      while (session.deviceInfo == null && DateTime.now().isBefore(handshakeDeadline)) {
        if (isCancelled?.call() ?? false) break;
        await Future<void>.delayed(_pollInterval);
      }
      if (session.deviceInfo == null) {
        return CaptureOutcome.failure(
          'No device-info response from the BMS (frame 0x03). Is this a JK-BMS?',
        );
      }

      await ble.write(
        BmsProtocolHelper.buildJk02Command(BmsProtocolHelper.jk02CommandCellInfo),
      );

      final deadline = DateTime.now().add(duration);
      while (DateTime.now().isBefore(deadline)) {
        if (isCancelled?.call() ?? false) break;
        onProgress?.call(_progress(session, 'Capturing telemetry…'));
        await Future<void>.delayed(_pollInterval);
      }
      onProgress?.call(_progress(session, 'Finishing…'));

      if (session.statuses.isEmpty) {
        return CaptureOutcome.failure(
          'No cell-info frames arrived (frame 0x02). Nothing to contribute.',
        );
      }

      // Best-effort logbook read; a device that ignores it changes nothing.
      try {
        await ble.write(BmsProtocolHelper.buildJk02LogbookRequest());
        await Future<void>.delayed(_pollInterval);
      } catch (_) {}

      final samples = <TelemetrySample>[];
      for (var i = 0; i < session.statuses.length; i++) {
        samples.add(TelemetrySample.fromStatus(
          session.statuses[i],
          tOffsetMs: session.statusOffsetsMs[i],
        ));
      }

      final contribution = Contribution.fromCapture(
        app: app,
        remoteId: device.id,
        advertisedName: device.name,
        rssi: ble.rssi != 0 ? ble.rssi : device.rssi,
        serviceUuids: ble.serviceUuids.isNotEmpty ? ble.serviceUuids : device.serviceUuids,
        deviceInfo: session.deviceInfo,
        is32s: session.is32s,
        samples: samples,
        rawFrames: session.rawFrames,
        settingsValues: session.settingsValues,
        logbookEntries: session.logbookEntries.isEmpty ? null : session.logbookEntries,
        includeSerial: includeSerial,
      );

      return CaptureOutcome.success(contribution, session);
    } catch (e) {
      return CaptureOutcome.failure('Capture failed: $e');
    } finally {
      await subscription?.cancel();
      try {
        await ble?.disconnect();
      } catch (_) {}
    }
  }

  CaptureProgress _progress(Jk02CaptureSession session, String status) => CaptureProgress(
        status: status,
        fragmentCount: session.fragmentCount,
        frameCount: session.frameCount,
        sampleCount: session.statuses.length,
      );
}
