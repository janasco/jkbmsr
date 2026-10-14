// Generates the Play Store screenshots for JK BMS Contributor.
//
// WHY THIS IS A TEST FILE IN `tool/` AND NOT IN `test/`
//   `flutter test` only picks up `test/**`, so nothing here runs as part of the
//   normal suite — this is a generator, not an assertion. Run it explicitly:
//
//       flutter test tool/generate_store_screenshots.dart
//
//   Output lands in `build/store-screenshots/` (gitignored); copy the PNGs to
//   `jkbmsr-private/brand/content/play-listing/contributor-screenshots/`.
//
// WHY IT IS HONEST
//   There is no Android emulator on this host (/dev/kvm is absent and `mknod` is
//   denied even as root), so a device capture is impossible here. This does NOT
//   draw a picture of the app: it mounts the app's own widgets, with the app's
//   own ThemeData, and photographs what Flutter actually renders. The review
//   screen is fed `sampleContribution()`, which is built from the real
//   JK-B2A24S capture, so the values on screen are real decoded data rather than
//   invented ones.
//
//   Real fonts matter: a widget test otherwise uses Flutter's placeholder test
//   font, which renders as boxes and makes every screenshot useless. The Roboto
//   TTFs are loaded from the SDK, resolved through FLUTTER_ROOT rather than a
//   hard-coded host path.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_contributor/models/contribution.dart';
import 'package:jkbmsr_contributor/screens/capture_screen.dart';
import 'package:jkbmsr_contributor/screens/consent_screen.dart';
import 'package:jkbmsr_contributor/screens/home_screen.dart';
import 'package:jkbmsr_contributor/screens/review_screen.dart';
import 'package:jkbmsr_contributor/services/app_info.dart';
import 'package:jkbmsr_contributor/services/ble_transport.dart';
import 'package:jkbmsr_contributor/services/capture_service.dart';
import 'package:jkbmsr_contributor/services/consent_controller.dart';
import 'package:jkbmsr_contributor/services/consent_store.dart';

import '../test/support/fake_flutter_blue_plus.dart';
import '../test/support/jk02_fixtures.dart';

/// Play wants phone screenshots between 320 and 3840 px. This renders a real
/// phone's metrics — 1080×2340 physical at DPR 3, i.e. 360×780 *logical* — so
/// the layout is a phone layout rather than a tablet one, and the output PNG is
/// a crisp 1080×2340 (the same shape the live JK BMS Bluetooth listing uses).
const Size _phone = Size(1080, 2340);
const double _dpr = 3.0;

const String _outDir = 'build/store-screenshots';

/// The app's own theme, from `main.dart` — not a stand-in.
ThemeData _theme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: AppInfo.brandColor),
    );

/// Loads the SDK's real Roboto faces so text renders as text.
Future<void> _loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  final loader = FontLoader('Roboto');
  var any = false;
  for (final face in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
    final file = File('${dir.path}/$face');
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
    any = true;
  }
  if (any) await loader.load();
}

/// Mounts [home] at the phone frame inside a repaint boundary.
Future<GlobalKey> _mount(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = _dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(key: key, child: MaterialApp(theme: _theme(), home: home)),
  );
  await tester.pumpAndSettle();
  return key;
}

/// Writes what is actually on screen to `<out>/<name>.png`.
Future<void> _shoot(WidgetTester tester, GlobalKey key, String name) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final dir = Directory(_outDir)..createSync(recursive: true);
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
  // A zero-byte or non-square file would be a silent failure; assert instead.
  final written = File('${dir.path}/$name.png');
  expect(written.lengthSync(), greaterThan(10000), reason: '$name looks empty');
}

/// The minimum `CaptureController` the capture screen needs, mirroring the fake
/// the real screen test uses. Returns the real capture, so the screen shows real
/// decoded values.
class _FakeCaptureController implements CaptureController {
  @override
  Future<bool> isSupported() async => true;

  @override
  Stream<List<BleScanResult>> scan({Duration timeout = const Duration(seconds: 1)}) =>
      Stream.value(const [
        BleScanResult(
          id: 'AA:BB:CC:11:22:33',
          name: 'JK_B2A24S15P',
          rssi: -63,
          serviceUuids: ['0000ffe0-0000-1000-8000-00805f9b34fb'],
        ),
      ]);

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
    return CaptureOutcome.success(sampleContribution(), Jk02CaptureSession());
  }
}

void main() {
  setUp(installFakeFlutterBluePlus);

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadRoboto();
  });

  testWidgets('01 consent — the blocking first-run screen', (tester) async {
    final key = await _mount(
      tester,
      ConsentScreen(controller: ConsentController(store: InMemoryConsentStore())),
    );
    await _shoot(tester, key, '01-consent');
  });

  testWidgets('02 home', (tester) async {
    final key = await _mount(tester, const HomeScreen());
    await _shoot(tester, key, '02-home');
  });

  testWidgets('03 capture — after a real capture completes', (tester) async {
    final key = await _mount(tester, CaptureScreen(controller: _FakeCaptureController()));
    await tester.tap(find.text('Scan for JK-BMS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JK_B2A24S15P'));
    await tester.pumpAndSettle();
    await _shoot(tester, key, '03-capture');
  });

  testWidgets('04 review — the payload, field by field', (tester) async {
    final key = await _mount(
      tester,
      ReviewScreen(
        contribution: sampleContribution(),
        rawSerial: '2021602096',
        consent: ConsentRecord(givenAt: DateTime.utc(2026, 10, 14, 9, 30), scope: 'telemetry+frames'),
      ),
    );
    await _shoot(tester, key, '04-review');
  });

  testWidgets('05 review — scrolled to the per-field controls', (tester) async {
    final key = await _mount(
      tester,
      ReviewScreen(
        contribution: sampleContribution(),
        rawSerial: '2021602096',
        consent: ConsentRecord(givenAt: DateTime.utc(2026, 10, 14, 9, 30), scope: 'telemetry+frames'),
      ),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    await _shoot(tester, key, '05-review-fields');
  });
}
