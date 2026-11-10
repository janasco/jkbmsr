import 'dart:async';

import 'package:bms_core/bms_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../l10n/strings.dart';
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
/// Reassembles JK02 frames from BLE notifications.
///
/// Reassembly is over the BYTE STREAM, not over notification boundaries. Two
/// things happen in the field that the old fragment-boundary version could not
/// survive:
///
///  * a notification may begin mid-frame — after a dropped packet, or because a
///    larger MTU splits a frame at a non-multiple of the frame size; and
///  * a notification may carry more than one frame.
///
/// Both matter directly: the logbook (0x05) is a single 300-byte response
/// requested in the middle of the cell-info stream, so it commonly shares a
/// notification with the tail of a cell-info frame. The old code resynced only
/// when a *fragment* began with the magic, kept at most one frame's worth of
/// bytes and returned one frame per notification, so that logbook frame was
/// discarded even though the device had sent it.
class Jk02FrameAccumulator {
  static const int frameSize = 300;
  static const List<int> _magic = [0x55, 0xAA, 0xEB, 0x90];

  final List<int> _buffer = [];

  void reset() => _buffer.clear();

  /// Feeds one notification; returns every complete, CRC-valid frame it
  /// completed — usually zero or one, but never fewer than are actually there.
  List<List<int>> add(List<int> fragment) {
    _buffer.addAll(fragment);
    final frames = <List<int>>[];
    while (true) {
      final start = _magicIndex;
      if (start < 0) {
        // No frame start anywhere. Only the last three bytes can be the
        // beginning of a magic, so everything before them is unusable and must
        // not be allowed to accumulate.
        if (_buffer.length > _magic.length - 1) {
          _buffer.removeRange(0, _buffer.length - (_magic.length - 1));
        }
        break;
      }
      if (start > 0) _buffer.removeRange(0, start);
      if (_buffer.length < frameSize) break;
      final candidate = _buffer.sublist(0, frameSize);
      if (BmsProtocolHelper.isCompleteJk02Frame(candidate)) {
        frames.add(candidate);
        _buffer.removeRange(0, frameSize);
        continue;
      }
      // A magic that did not begin a valid frame. Step one byte and look again
      // rather than discarding a whole window, which could throw away a real
      // frame that started inside it.
      _buffer.removeRange(0, 1);
    }
    return frames;
  }

  int get _magicIndex {
    for (var i = 0; i + _magic.length <= _buffer.length; i++) {
      if (_buffer[i] == _magic[0] &&
          _buffer[i + 1] == _magic[1] &&
          _buffer[i + 2] == _magic[2] &&
          _buffer[i + 3] == _magic[3]) {
        return i;
      }
    }
    return -1;
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

  /// Set only for a failure with a classified cause (Bluetooth off, out of
  /// range), for the error view's icon; a protocol failure carries no kind and
  /// a success carries none either.
  final BleCaptureFailureKind? failureKind;

  const CaptureOutcome._({
    this.contribution,
    this.session,
    this.error,
    this.failureKind,
  });

  bool get success => contribution != null;

  factory CaptureOutcome.success(Contribution contribution, Jk02CaptureSession session) =>
      CaptureOutcome._(contribution: contribution, session: session);

  factory CaptureOutcome.failure(String error, {BleCaptureFailureKind? failureKind}) =>
      CaptureOutcome._(error: error, failureKind: failureKind);
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
    for (final frame in _accumulator.add(fragment)) {
      _ingestFrame(frame);
    }
  }

  void _ingestFrame(List<int> frame) {
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
  /// [log] is an injectable seam (like `UniversalBleTransport.log`) that
  /// records the raw reason a capture failed — which is never shown to the
  /// user.
  CaptureService({required BleTransport transport, void Function(String message)? log})
      : _transport = transport,
        _log = log ?? debugPrint;

  final BleTransport _transport;
  final void Function(String message) _log;

  /// How long to wait for the device-info (0x03) handshake before giving up.
  static const Duration defaultHandshakeTimeout = Duration(seconds: 5);

  /// The default capture window offered by the UI.
  static const Duration defaultDuration = Duration(seconds: 30);

  /// How long to wait for the logbook (0x05) after requesting it.
  ///
  /// The device answers 0xA1 with a full 300-byte frame in the middle of the
  /// telemetry stream, so it cannot be assumed to arrive within a poll tick. The
  /// capture used to wait a fixed 50 ms and disconnect, which is why no
  /// contribution has ever carried a logbook entry even though the request was
  /// being sent and the devices do answer it.
  static const Duration defaultLogbookTimeout = Duration(seconds: 5);

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
    Duration logbookTimeout = defaultLogbookTimeout,
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
        return CaptureOutcome.failure(CaptureStrings.noDeviceInfo);
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
        return CaptureOutcome.failure(CaptureStrings.noCellInfo);
      }

      // The telemetry series is exactly what fell inside the capture window.
      // Freeze the count before the logbook wait: frames that arrive while we
      // are waiting for 0x05 are real and stay in `rawFrames`, but they are not
      // part of the window the payload declares.
      final windowedSamples = session.statuses.length;

      // Best-effort logbook read; a device that ignores it changes nothing.
      // Wait for the FRAME, not for a fixed delay — the answer is a 300-byte
      // frame competing with the telemetry stream.
      try {
        onProgress?.call(_progress(session, 'Reading the logbook…'));
        await ble.write(BmsProtocolHelper.buildJk02LogbookRequest());
        final logbookDeadline = DateTime.now().add(logbookTimeout);
        while (session.logbookEntries.isEmpty && DateTime.now().isBefore(logbookDeadline)) {
          if (isCancelled?.call() ?? false) break;
          await Future<void>.delayed(_pollInterval);
        }
        if (session.logbookEntries.isEmpty) {
          // Best-effort, but never silent: "the device ignored it" and "we
          // never asked" look identical in a payload that carries no logbook,
          // and only the log can tell them apart afterwards.
          _log('no logbook frame within ${logbookTimeout.inMilliseconds}ms');
        }
      } catch (e) {
        _log('logbook request failed: $e');
      }

      final samples = <TelemetrySample>[];
      for (var i = 0; i < windowedSamples; i++) {
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
      // A failure after the scan — Bluetooth switched off mid-session, the pack
      // going out of range, a GATT error — is classified like a scan failure:
      // the user gets a plain, actionable sentence plus the existing retry,
      // and the raw cause is kept here in the logs, never in the product text.
      // `ble != null` tells the classifier whether the link was already up, so
      // a timeout mid-capture is not reported as the pack moving away.
      final failure = classifyCaptureFailure(e, linkEstablished: ble != null);
      _log('Capture failed (${failure.kind.name}): ${failure.cause ?? e}');
      return CaptureOutcome.failure(
        CaptureStrings.captureFailure(failure.kind),
        failureKind: failure.kind,
      );
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
