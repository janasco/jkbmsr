import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_contributor/l10n/strings.dart';
import 'package:jkbmsr_contributor/models/contribution.dart';
import 'package:jkbmsr_contributor/screens/capture_screen.dart';
import 'package:jkbmsr_contributor/services/ble_transport.dart';
import 'package:jkbmsr_contributor/services/capture_service.dart';

import '../support/fake_flutter_blue_plus.dart';
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

void main() {
  setUp(installFakeFlutterBluePlus);

  testWidgets('scan -> select -> summary shows what was captured',
      (WidgetTester tester) async {
    final controller = FakeCaptureController();
    await tester.pumpWidget(MaterialApp(home: CaptureScreen(controller: controller)));

    expect(find.text('Scan for JK-BMS'), findsOneWidget);

    await tester.tap(find.text('Scan for JK-BMS'));
    await tester.pumpAndSettle();
    expect(controller.scanCalls, 1);
    expect(find.text('JK_B2A24S15P'), findsOneWidget);

    await tester.tap(find.text('JK_B2A24S15P'));
    await tester.pumpAndSettle();

    // The summary lists the decoded identity and the anonymisation default.
    expect(find.text('Captured'), findsOneWidget);
    expect(find.text('JK-B2A24S15P'), findsOneWidget);
    expect(find.text('withheld'), findsOneWidget);
    expect(find.textContaining('bytes'), findsWidgets);

    // The review/submit seam is present but leads nowhere yet.
    expect(find.text('Review & contribute'), findsOneWidget);
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
