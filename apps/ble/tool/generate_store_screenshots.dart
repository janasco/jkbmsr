// Generates the Play Store screenshots for JK BMS Bluetooth.
//
// WHY THIS IS A TEST FILE IN `tool/` AND NOT IN `test/`
//   `flutter test` only picks up `test/**`, so nothing here runs with the suite.
//   Run it explicitly:
//
//       flutter test tool/generate_store_screenshots.dart
//
//   Output lands in `build/store-screenshots/` (gitignored). The framing step and
//   the upload are documented in
//   `jkbmsr-private/brand/content/play-listing/ble-screenshots/README.md`.
//
// WHY IT IS HONEST
//   There is no Android emulator on this host, so a device capture is impossible.
//   This mounts the app's own widgets with the app's own theme and bundled
//   typeface, and photographs what Flutter renders. The pack is seeded through
//   `BleBmsService.debugPublishStatus`, the same data model a real frame produces,
//   so no value on screen is drawn or invented.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/models/bms_models.dart';
import 'package:jkbmsr_ble/screens/cells_screen.dart';
import 'package:jkbmsr_ble/screens/controls_screen.dart';
import 'package:jkbmsr_ble/screens/status_screen.dart';
import 'package:jkbmsr_ble/screens/welcome_screen.dart';
import 'package:jkbmsr_ble/services/ble_service.dart';

/// A real phone's metrics: 1080x2340 physical at DPR 3, i.e. 360x780 logical.
const Size _phone = Size(1080, 2340);
const double _dpr = 3.0;
const String _outDir = 'build/store-screenshots';

ThemeData _theme() => ThemeData(
      // `fontFamily` on ThemeData, not only on textTheme: the screens build most
      // labels from a bare TextStyle, which merges with the material default, and
      // in the test harness that default was the engine's tofu font.
      fontFamily: 'JakartaRender',
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      primaryColor: const Color(0xFF10B981),
      cardColor: const Color(0xFFFFFFFF),
      dividerColor: const Color(0xFFE2E8F0),
      textTheme: ThemeData.light().textTheme.apply(fontFamily: 'JakartaRender'),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF10B981),
        secondary: Color(0xFF0284C7),
        surface: Color(0xFFFFFFFF),
        error: Color(0xFFEF4444),
      ),
    );

/// The bundled typeface, loaded from the app's own assets.
///
/// A widget test otherwise renders Flutter's placeholder font, which is boxes: the
/// first BLE store set was made before the font was bundled and every label was a
/// tofu square.
Future<void> _loadFonts() async {
  // The SDK's own faces first: MaterialIcons for every icon, Roboto as the
  // fallback for any style that names no family. Without MaterialIcons every icon
  // is an empty box, which is how the first BLE set shipped.
  final root = Platform.environment['FLUTTER_ROOT'];
  final dir = root == null ? null : Directory('$root/bin/cache/artifacts/material_fonts');
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    var any = false;
    for (final path in paths) {
      final file = File(path);
      debugPrint('  font ${file.existsSync() ? "ok  " : "MISS"} $path (cwd ${Directory.current.path})');
      if (!file.existsSync()) continue;
      loader.addFont(Future.value(ByteData.sublistView(Uint8List.fromList(file.readAsBytesSync()))));
      any = true;
    }
    if (any) await loader.load();
  }

  if (dir != null && dir.existsSync()) {
    await load('Roboto', [
      '${dir.path}/Roboto-Regular.ttf',
      '${dir.path}/Roboto-Medium.ttf',
      '${dir.path}/Roboto-Bold.ttf',
    ]);
    await load('MaterialIcons', ['${dir.path}/MaterialIcons-Regular.otf']);
  }

  // Then the app's bundled typeface, which the theme asks for by name.
  // A render-only family name. Registering under the app's own family name
  // produced tofu: the test bundle also declares `PlusJakartaSans` (without the
  // asset behind it), and the engine resolved that empty declaration instead of
  // the faces registered here.
  await load('JakartaRender', ['assets/fonts/PlusJakartaSans-Regular.ttf']);

  // The app renders every numeric value with `fontFamily: 'monospace'`, which
  // Android resolves and the test engine does not: without this, each figure was a
  // solid block. DejaVu Sans Mono is a real monospace face on the build host.
  await load('monospace', [
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf',
  ]);
}

/// A 16-cell 48 V pack under a 24 A load, with a small real spread so the balance
/// state reads as balanced rather than perfect.
BmsStatus _status() {
  final cells = <CellInfo>[
    for (var i = 0; i < 16; i++)
      CellInfo(
        index: i + 1,
        voltage: 3.318 + ((i % 5) - 2) * 0.002,
        wireResistance: 0.0012 + (i % 3) * 0.0002,
        isBalancing: false,
      ),
  ];
  return BmsStatus(
    brand: BmsBrand.jkbms,
    modelName: 'JK-B2A24S15P',
    soc: 78,
    totalVoltage: 53.12,
    currentA: -24.0,
    powerW: -1275,
    remainingCapacityAh: 218.4,
    nominalCapacityAh: 280,
    cycleCount: 342,
    totalCycleCapacityAh: 91840,
    cells: cells,
    timestamp: DateTime(2026, 11, 24, 9, 41),
    mosTemp: 31.2,
    t1Temp: 27.8,
    t2Temp: 28.1,
    enabledCellCount: 16,
  );
}

Future<GlobalKey> _mount(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = _dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // ignore: invalid_use_of_visible_for_testing_member — this is a tool, not the app
  BleBmsService().debugPublishStatus(_status());

  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        theme: _theme(),
        debugShowCheckedModeBanner: false,
        // The app shell supplies Material above every screen, so ink and the
        // ambient text style exist. Mounting a screen directly does not, and a
        // control screen renders Flutter's red "No Material widget found" panel.
        home: Material(child: screen),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return key;
}

Future<void> _shoot(WidgetTester tester, GlobalKey key, String name) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final file = File('$_outDir/$name.png');
  file.parent.createSync(recursive: true);
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
  expect(file.lengthSync(), greaterThan(10000), reason: '$name looks empty');
}

/// Mount, shoot, then tear the tree down so no screen's timer outlives the test.
Future<void> _render(WidgetTester tester, Widget screen, String name) async {
  final key = await _mount(tester, screen);
  await _shoot(tester, key, name);
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 7)));
    await tester.pump(const Duration(seconds: 30));
  }
}

void main() {
  // Fonts are registered per test, not once in setUpAll: in this harness a family
  // registered in setUpAll was not visible to the engine, and every label rendered
  // as the test font's tofu box while the icons (loaded the same way) were fine.
  setUp(() async {
    await _loadFonts();
  });

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final out = Directory(_outDir);
    if (out.existsSync()) {
      for (final entity in out.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.png')) entity.deleteSync();
      }
    }
  });

  testWidgets('01 status', (tester) async {
    await _render(tester, const StatusScreen(), '01-status');
  });

  testWidgets('02 cells', (tester) async {
    await _render(tester, const CellsScreen(), '02-cells');
  });

  testWidgets('03 controls', (tester) async {
    await _render(tester, const ControlsScreen(), '03-controls');
  });

  testWidgets('04 welcome', (tester) async {
    await _render(tester, WelcomeScreen(onStartScanning: () {}), '04-welcome');
  });
}
