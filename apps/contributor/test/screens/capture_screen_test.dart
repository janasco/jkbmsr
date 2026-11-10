import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_contributor/l10n/strings.dart';
import 'package:jkbmsr_contributor/models/contribution.dart';
import 'package:jkbmsr_contributor/screens/capture_screen.dart';
import 'package:jkbmsr_contributor/services/ble_transport.dart';
import 'package:jkbmsr_contributor/services/capture_service.dart';
import 'package:jkbmsr_contributor/widgets/rotating_glyph.dart';

import '../support/fake_universal_ble.dart';
import '../support/jk02_fixtures.dart';

const _device = BleScanResult(
  id: 'AA:BB:CC:11:22:33',
  name: 'JK_B2A24S15P',
  rssi: -63,
  serviceUuids: ['0000ffe0-0000-1000-8000-00805f9b34fb'],
);

class FakeCaptureController implements CaptureController {
  FakeCaptureController({this.returnSuccess = true, this.scanErrors = const []});

  final bool returnSuccess;

  /// One entry per `scan()` call: the object the scan stream errors with, or
  /// null for a successful scan. Lets a test script "fails once, then works".
  final List<Object?> scanErrors;
  int scanCalls = 0;

  @override
  Future<bool> isSupported() async => true;

  @override
  Stream<List<BleScanResult>> scan({Duration timeout = const Duration(seconds: 1)}) {
    final index = scanCalls++;
    // Emit through a StreamController that closes, exactly as the real
    // transport does: `Stream.error` leaves a subscription whose `cancel()`
    // does not complete promptly, which is not what the screen faces in
    // production.
    final stream = StreamController<List<BleScanResult>>();
    scheduleMicrotask(() {
      if (index < scanErrors.length && scanErrors[index] != null) {
        stream.addError(scanErrors[index]!);
      } else {
        stream.add([_device]);
      }
      stream.close();
    });
    return stream.stream;
  }

  @override
  Future<CaptureOutcome> capture(
    BleScanResult device, {
    Duration duration = CaptureService.defaultDuration,
    Duration handshakeTimeout = CaptureService.defaultHandshakeTimeout,
    bool includeSerial = false,
    required AppProvenance app,
    bool Function()? isCancelled,
    void Function(CaptureProgress progress)? onProgress,
  }) async {
    onProgress?.call(const CaptureProgress(
      status: 'Capturing telemetry…',
      fragmentCount: 30,
      frameCount: 2,
      sampleCount: 1,
    ));
    if (!returnSuccess) return CaptureOutcome.failure('boom');
    return CaptureOutcome.success(sampleContribution(), Jk02CaptureSession());
  }
}

/// A capture that never finishes, so the in-progress screen can be inspected
/// and advanced with the test clock.
class _PendingCaptureController implements CaptureController {
  _PendingCaptureController(this.completer);

  final Completer<CaptureOutcome> completer;

  @override
  Future<bool> isSupported() async => true;

  @override
  Stream<List<BleScanResult>> scan({Duration timeout = const Duration(seconds: 1)}) =>
      Stream.value(const [_device]);

  @override
  Future<CaptureOutcome> capture(
    BleScanResult device, {
    Duration duration = CaptureService.defaultDuration,
    Duration handshakeTimeout = CaptureService.defaultHandshakeTimeout,
    bool includeSerial = false,
    required AppProvenance app,
    bool Function()? isCancelled,
    void Function(CaptureProgress progress)? onProgress,
  }) {
    onProgress?.call(const CaptureProgress(
      status: 'Capturing telemetry…',
      fragmentCount: 5,
      frameCount: 1,
      sampleCount: 1,
    ));
    return completer.future;
  }
}

void main() {
  setUp(installFakeUniversalBle);

  testWidgets('scan -> select -> the result is its own screen', (WidgetTester tester) async {
    final controller = FakeCaptureController();
    await tester.pumpWidget(MaterialApp(home: CaptureScreen(controller: controller)));

    expect(find.text('Scan for JK-BMS'), findsOneWidget);

    await tester.tap(find.text('Scan for JK-BMS'));
    await tester.pumpAndSettle();
    expect(controller.scanCalls, 1);
    expect(find.text('JK_B2A24S15P'), findsOneWidget);

    await tester.tap(find.text('JK_B2A24S15P'));
    await tester.pumpAndSettle();

    // A separate route, not a list appended under the spinner. It states what
    // was captured and that nothing has been sent.
    expect(find.text('Contribution ready'), findsOneWidget);
    expect(find.text('JK-B2A24S15P'), findsOneWidget);
    expect(find.text('withheld'), findsOneWidget);
    expect(find.textContaining('bytes'), findsWidgets);
    expect(find.textContaining('Nothing has been sent yet'), findsOneWidget);

    // The review/submit seam is present.
    expect(find.text('Review & contribute'), findsOneWidget);

    // And the screen underneath went back to idle, so leaving does not land on
    // a dead progress bar.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Scan for JK-BMS'), findsOneWidget);
    expect(find.text('Contribution ready'), findsNothing);
  });

  testWidgets('Capture another pack returns to a fresh scan', (WidgetTester tester) async {
    final controller = FakeCaptureController();
    await tester.pumpWidget(MaterialApp(home: CaptureScreen(controller: controller)));

    await tester.tap(find.text('Scan for JK-BMS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JK_B2A24S15P'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Capture another pack'));
    // The screen cancels the previous scan subscription before starting the
    // next one; the widget-test clock does not drive that future (the same
    // nudge the retry test below needs).
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(controller.scanCalls, 2);
    expect(find.text('JK_B2A24S15P'), findsOneWidget);
  });

  testWidgets('while capturing, the bar advances and the glyph changes',
      (WidgetTester tester) async {
    final completer = Completer<CaptureOutcome>();
    final controller = _PendingCaptureController(completer);
    await tester.pumpWidget(MaterialApp(
      home: CaptureScreen(
        controller: controller,
        captureDuration: const Duration(seconds: 10),
      ),
    ));

    await tester.tap(find.text('Scan for JK-BMS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JK_B2A24S15P'));
    await tester.pump();

    expect(find.text('Capturing'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('Samples'), findsOneWidget);
    expect(find.text('Frames'), findsOneWidget);

    IconData glyph() => tester
        .widget<Icon>(find
            .descendant(
              of: find.byType(RotatingGlyph),
              matching: find.byType(Icon),
            )
            .first)
        .icon!;
    final first = glyph();

    // Five seconds into a ten-second window: the bar tracks it.
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('50%'), findsOneWidget);

    // Let the glyph cross-fade finish, then require that it moved.
    await tester.pump(const Duration(milliseconds: 400));
    expect(glyph(), isNot(first), reason: 'the orb should move while it works');

    // Let it finish so no animation or future is left pending.
    completer.complete(CaptureOutcome.failure('boom'));
    await tester.pumpAndSettle();
    expect(find.text('boom'), findsOneWidget);
  });

  testWidgets('a failed capture shows the error state', (WidgetTester tester) async {
    final controller = FakeCaptureController(returnSuccess: false);
    await tester.pumpWidget(MaterialApp(home: CaptureScreen(controller: controller)));

    await tester.tap(find.text('Scan for JK-BMS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JK_B2A24S15P'));
    await tester.pumpAndSettle();

    expect(find.text('boom'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets(
      'a capture failure after a good scan shows a plain message, logs the raw '
      'cause, and retries — never the raw exception', (WidgetTester tester) async {
    // This drives the *real* CaptureService over a transport that fails the
    // post-handshake write, so the whole classify→copy→screen path is exercised
    // with a genuine PlatformException, not a hand-fed string.
    final transport = _FailingCaptureTransport(
      error: PlatformException(
        code: 'connect',
        message: 'Bluetooth must be turned on',
      ),
    );
    final logs = <String>[];
    final service = CaptureService(transport: transport, log: logs.add);
    await tester.pumpWidget(MaterialApp(home: CaptureScreen(controller: service)));

    await tester.tap(find.text('Scan for JK-BMS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JK_B2A24S15P'));
    // The capture awaits its stream subscription's `cancel()` at the end,
    // whose future the widget-test fake clock does not drive (same reason the
    // scan retry below nudges it); let it finish, then settle the error view.
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(
      find.text(CaptureStrings.captureFailure(BleCaptureFailureKind.bluetoothOff)),
      findsOneWidget,
    );
    expect(find.textContaining('PlatformException'), findsNothing);
    expect(find.textContaining('Capture failed'), findsNothing);
    expect(find.byIcon(Icons.bluetooth_disabled_rounded), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // The raw reason is kept for the logs.
    expect(logs.join('\n'), contains('Bluetooth must be turned on'));

    // Retry restarts the scan and finds the device again.
    await tester.tap(find.text('Try again'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('JK_B2A24S15P'), findsOneWidget);
  });

  testWidgets(
      'Bluetooth off shows a plain, actionable message — never the raw '
      'PlatformException — with a retry that works', (WidgetTester tester) async {
    // The exact error flutter_blue_plus throws on Android when the adapter is
    // off (see its `result.error("startScan", "Bluetooth must be turned on")`).
    // This is the bug the owner hit: the raw string used to reach the screen.
    final controller = FakeCaptureController(scanErrors: [
      PlatformException(code: 'startScan', message: 'Bluetooth must be turned on'),
      null, // the retry succeeds
    ]);
    await tester.pumpWidget(MaterialApp(home: CaptureScreen(controller: controller)));

    await tester.tap(find.text('Scan for JK-BMS'));
    await tester.pumpAndSettle();

    // The friendly sentence, and no trace of the exception anywhere on screen.
    expect(
      find.text('Bluetooth is off. Turn Bluetooth on to scan for your JK-BMS.'),
      findsOneWidget,
    );
    expect(find.textContaining('PlatformException'), findsNothing);
    expect(find.textContaining('startScan'), findsNothing);
    expect(find.textContaining('Scan failed'), findsNothing);
    expect(find.byIcon(Icons.bluetooth_disabled_rounded), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    // Retry: the second scan succeeds and the device is listed.
    await tester.tap(find.text('Try again'));
    // The screen awaits the previous subscription's `cancel()`, whose future
    // the widget-test fake clock does not drive; nudge it with real async
    // (on a device there is no fake clock and this resolves immediately).
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(controller.scanCalls, 2);
    expect(find.text('JK_B2A24S15P'), findsOneWidget);
  });

  testWidgets('a permission failure is reported specifically, not swallowed',
      (WidgetTester tester) async {
    final controller = FakeCaptureController(scanErrors: [
      PlatformException(
        code: 'startScan',
        message: 'Permission BLUETOOTH_SCAN required to scan devices',
      ),
    ]);
    await tester.pumpWidget(MaterialApp(home: CaptureScreen(controller: controller)));

    await tester.tap(find.text('Scan for JK-BMS'));
    await tester.pumpAndSettle();

    expect(
      find.text(ScanStrings.scanFailure(BleScanFailureKind.permissionDenied)),
      findsOneWidget,
    );
    expect(find.textContaining('PlatformException'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('an unexpected scan failure still shows a sensible message, not silence',
      (WidgetTester tester) async {
    final controller = FakeCaptureController(scanErrors: [StateError('weird')]);
    await tester.pumpWidget(MaterialApp(home: CaptureScreen(controller: controller)));

    await tester.tap(find.text('Scan for JK-BMS'));
    await tester.pumpAndSettle();

    expect(find.text(ScanStrings.scanFailure(BleScanFailureKind.other)), findsOneWidget);
    expect(find.textContaining('weird'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });
}

/// A transport whose session answers the device-info handshake, then fails the
/// following write — the shape of a mid-capture failure (adapter off, out of
/// range, GATT error) — so the screen can be driven with a real raw exception.
class _FailingCaptureTransport implements BleTransport {
  _FailingCaptureTransport({required this.error});

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
  Future<BleSession> connect(String deviceId) async => _FailingSession(error);
}

class _FailingSession implements BleSession {
  _FailingSession(this.error);

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
      for (final fragment in chunk(bytesFromHex(devInfo24sHex))) {
        _controller.add(fragment);
      }
      return;
    }
    throw error;
  }

  @override
  Future<void> disconnect() async {
    await _controller.close();
  }
}
