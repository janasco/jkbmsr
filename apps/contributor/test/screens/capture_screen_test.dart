import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  FakeCaptureController({this.returnSuccess = true});

  final bool returnSuccess;
  int scanCalls = 0;

  @override
  Future<bool> isSupported() async => true;

  @override
  Stream<List<BleScanResult>> scan({Duration timeout = const Duration(seconds: 1)}) {
    scanCalls++;
    return Stream.value([_device]);
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
}
