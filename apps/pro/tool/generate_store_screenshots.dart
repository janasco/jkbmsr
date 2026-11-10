// Renders the Pro app's real screens to PNGs, with a stubbed API.
//
// WHY THIS EXISTS
//   A redesign judged from a palette list is a guess. There is no Android emulator
//   on this host (/dev/kvm is absent, `mknod` is denied even as root), so these are
//   **renders of the app's own widget tree** — the real screens, the real
//   JKBMSRTheme, the real typography — at a real phone's metrics (1080x2340 at
//   DPR 3, i.e. 360x780 logical). Nothing is drawn by hand.
//
//   The API is stubbed at the same seam the tests use (`APIClient.configure(client:)`
//   with a `MockClient`), so the dashboard renders a populated pack rather than an
//   empty state. The values are representative, not real captures — unlike the
//   Contributor's generator there is no donated dataset to draw from.
//
// Run explicitly; `tool/` is not part of the test suite:
//
//   flutter test tool/generate_store_screenshots.dart
//
// Output lands in `build/screens/` (gitignored). Dark-mode proof shots go under
// `build/screens/verify/` so a non-recursive copy of the directory is the set.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jkbmsr_pro/features/alerts/alerts_screen.dart';
import 'package:jkbmsr_pro/features/auth/login_screen.dart';
import 'package:jkbmsr_pro/features/battery/battery_dashboard_screen.dart';
import 'package:jkbmsr_pro/features/battery/cell_voltages_screen.dart';
import 'package:jkbmsr_pro/features/devices/device_list_screen.dart';
import 'package:jkbmsr_pro/features/history/telemetry_history_screen.dart';
import 'package:jkbmsr_pro/features/onboarding/onboarding_screen.dart';
import 'package:jkbmsr_pro/features/settings/settings_screen.dart';
import 'package:jkbmsr_pro/services/api_client.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

const Size _phone = Size(1080, 2340);
const double _dpr = 3.0;
const String _outDir = 'build/screens';

/// Loads the SDK's real faces. Without them every glyph is the widget-test
/// placeholder, and without MaterialIcons every icon is an empty box.
Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;

  Future<void> load(String family, List<String> faces) async {
    final loader = FontLoader(family);
    var any = false;
    for (final face in faces) {
      final file = File('${dir.path}/$face');
      if (!file.existsSync()) continue;
      loader.addFont(Future.value(ByteData.sublistView(Uint8List.fromList(file.readAsBytesSync()))));
      any = true;
    }
    if (any) await loader.load();
  }

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);

  // The app's own typefaces, from the bundle (they are declared in pubspec assets).
  // Registering them here rather than relying on google_fonts' asset lookup: in a
  // widget test that lookup does not resolve, so the mono numerals rendered as
  // empty boxes while everything else silently fell back to Roboto.
  Future<void> loadBundled(String family, List<String> faces) async {
    final loader = FontLoader(family);
    var any = false;
    for (final face in faces) {
      final file = File('assets/fonts/$face');
      if (!file.existsSync()) continue;
      loader.addFont(Future.value(ByteData.sublistView(Uint8List.fromList(file.readAsBytesSync()))));
      any = true;
    }
    if (any) await loader.load();
  }

  await loadBundled('IBMPlexSans', [
    'IBMPlexSans-Regular.ttf',
    'IBMPlexSans-Medium.ttf',
    'IBMPlexSans-SemiBold.ttf',
    'IBMPlexSans-Bold.ttf',
  ]);
  await loadBundled('IBMPlexMono', [
    'IBMPlexMono-Regular.ttf',
    'IBMPlexMono-Medium.ttf',
    'IBMPlexMono-Bold.ttf',
  ]);
}

// ─── the stubbed API ─────────────────────────────────────────────────────────

const _deviceId = 'jkbmsr-4d7275d5';

Map<String, dynamic> _device() => {
      'id': _deviceId,
      'name': 'Garage pack',
      'status': 'online',
      'targetHardware': 'esp32-s3-16mb',
      'otaChannel': 'stable',
      'soc': 84,
      'voltage': 53.24,
      'current': -12.4,
      'firmwareVersion': '0.9.9',
      'lastSeen': DateTime.now().toUtc().toIso8601String(),
      'latestFirmwareVersion': '0.9.9',
      'updateAvailable': false,
      'expectedIntervalSeconds': 60,
      'secondsSinceLastTelemetry': 12,
      'secondsUntilNextExpectedCheckIn': 48,
      'isOwner': true,
      'dashboardTemplateMobile': 'default',
      'subscriptionTierId': 'cloud',
      'subscriptionTierLabel': 'Cloud',
    };

Map<String, dynamic> _telemetry() => {
      'voltage': 53.24,
      'current': -12.4,
      'power': 660.2,
      'soc': 84,
      'temperature1': 22.4,
      'temperature2': 21.8,
      // Unique voltages, 0.5 mV apart. The old `i % 5` pattern repeated every
      // five cells, so a store screenshot showed TWO cells labelled MIN and two
      // labelled MAX — which reads as a bug in the product.
      'cells': [
        for (var i = 0; i < 16; i++) {'cell': i + 1, 'voltage': 3.3270 + i * 0.0005},
      ],
      // Keys must match BmsExtras.fromJson exactly: the first version of this
      // fixture guessed them, and the hero card rendered "0.0 of 0 Ah" - a
      // placeholder that would have shipped in a store screenshot.
      'bms': {
        'mosfetTemperature': 24.1,
        'minCellVoltage': 3.327,
        'maxCellVoltage': 3.3345,
        'avgCellVoltage': 3.331,
        'deltaCellVoltage': 0.0075,
        'minVoltageCell': 1,
        'maxVoltageCell': 16,
        'cycleCount': 42,
        'cycleCapacityAh': 4212.0,
        'fullCapacityAh': 100.0,
        'remainingCapacityAh': 84.2,
        'stateOfHealth': 99.4,
        'balancingCurrent': 0.02,
        'balancing': true,
        'charging': false,
        'discharging': true,
        'errorsBitmask': 0,
      },
      // A healthy, fully set-up gateway: the Pack status card renders only when
      // something is outstanding, so this keeps the dashboard's hero (state of
      // charge) as the first thing in the shot instead of a checklist.
      'diagnostics': {
        'bmsLinkUp': true,
        'bytesReceived': 184320,
        'ble': {'state': 'connected', 'lastError': '', 'rssi': -61},
      },
    };

List<Map<String, dynamic>> _history() {
  final now = DateTime.now().toUtc();
  return [
    for (var i = 0; i < 48; i++)
      {
        'timestamp': now.subtract(Duration(minutes: 30 * (48 - i))).toIso8601String(),
        'voltage': 52.9 + (i % 7) * 0.05,
        'current': -11.0 - (i % 4) * 0.4,
        'soc': 70 + (i * 14 / 47).round(),
        'temperature1': 21.5 + (i % 5) * 0.2,
      },
  ];
}

http.Client _stubApi() => MockClient((request) async {
      final path = request.url.path;
      Map<String, dynamic> body;
      if (path.endsWith('/v1/dashboard/devices')) {
        body = {'devices': [_device()]};
      } else if (path.contains('/v1/dashboard/devices/')) {
        if (path.endsWith('/history') || path.contains('/telemetry')) {
          body = {'points': _history()};
        } else if (path.endsWith('/alerts')) {
          body = {'alerts': [], 'hasMore': false};
        } else if (path.contains('/config')) {
          body = {'config': <String, dynamic>{}};
        } else if (path.contains('/wifi')) {
          body = {'target': null};
        } else if (path.contains('/ble') || path.contains('/events')) {
          body = {'events': []};
        } else {
          body = {'device': _device(), 'telemetry': _telemetry()};
        }
      } else if (path.endsWith('/v1/alerts') || path.contains('/alerts')) {
        body = {'alerts': [], 'hasMore': false};
      } else if (path.contains('/history')) {
        body = {'points': _history()};
      } else {
        body = <String, dynamic>{};
      }
      return http.Response(
        const JsonEncoder().convert(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

// ─── mounting ───────────────────────────────────────────────────────────────

Future<GlobalKey> _mount(WidgetTester tester, Widget screen, {ThemeData? theme}) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = _dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final key = GlobalKey();

  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        theme: theme ?? JKBMSRTheme.lightTheme,
        darkTheme: JKBMSRTheme.darkTheme,
        debugShowCheckedModeBanner: false,
        home: screen,
      ),
    ),
  );
  // NOT pumpAndSettle: the dashboard runs a one-second "next update" countdown, so
  // there is always another frame scheduled and settling can never finish. Bounded
  // pumps plus real async time let the API futures resolve, then stop.
  // Fake-clock pumps only. `runAsync` would run the stubbed API on the real
  // clock, which makes the dedupe service's 5 s TTL a REAL timer that the fake
  // clock can never fire — and the test then fails on a pending timer. The mock
  // client resolves in a microtask, so pumps are enough.
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return key;
}

Future<void> _shoot(WidgetTester tester, GlobalKey key, String name) async {
  final file = File('$_outDir/$name.png');
  file.parent.createSync(recursive: true);
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
  expect(file.lengthSync(), greaterThan(10000), reason: '$name looks empty');
}

/// Mount → shoot → tear the tree down. The teardown is not optional: screens with
/// a live countdown leave a periodic timer running, and flutter_test fails a test
/// whose timer outlives the tree.
Future<void> _render(WidgetTester tester, Widget screen, String name, {ThemeData? theme}) async {
  final key = await _mount(tester, screen, theme: theme);
  await _shoot(tester, key, name);
  // Remove the tree FIRST — disposing the router while the Router widget still
  // references it can skip the page teardown, leaving the screen's poll timer
  // running. The tree going away is what disposes the screen (and cancels it).
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  // The dedupe singleton holds a one-shot 5 s TTL Timer that is not widget-scoped.
  // Screenshots are encoded inside `runAsync`, which moves the completion of any
  // in-flight load onto the real clock — so that TTL is a REAL timer the fake
  // clock cannot fire. Wait it out for real, then drain the fake clock too.
  // Repeat: a load that completes during one wait starts a fresh 5 s TTL, which
  // then needs its own wait. Three rounds drains the chain.
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 7)));
    await tester.pump(const Duration(seconds: 30));
  }
}

void main() {
  setUp(() {
    // ignore: invalid_use_of_visible_for_testing_member — this is a test-owned tool
    SharedPreferences.setMockInitialValues({});
    // No network in a widget test; the SDK faces loaded above are the fallback.
    GoogleFonts.config.allowRuntimeFetching = false;
    APIClient.configure(baseUrl: 'https://test.local', client: _stubApi());
  });

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
    final out = Directory(_outDir);
    if (out.existsSync()) {
      for (final entity in out.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.png')) entity.deleteSync();
      }
    }
  });

  testWidgets('01 devices', (tester) async {
    final key = await _mount(tester, const DeviceListScreen());
    await _shoot(tester, key, '01-devices');
  });

  testWidgets('02 dashboard', (tester) async {
    final key = await _mount(tester, const BatteryDashboardScreen(deviceId: _deviceId));
    await _shoot(tester, key, '02-dashboard');
  });

  testWidgets('03 cells', (tester) async {
    final key = await _mount(tester, const CellVoltagesScreen());
    await _shoot(tester, key, '03-cells');
  });

  testWidgets('04 history', (tester) async {
    final key = await _mount(tester, const TelemetryHistoryScreen());
    await _shoot(tester, key, '04-history');
  });

  testWidgets('05 alerts', (tester) async {
    final key = await _mount(tester, const AlertsScreen());
    await _shoot(tester, key, '05-alerts');
  });

  testWidgets('06 onboarding', (tester) async {
    final key = await _mount(tester, const OnboardingScreen());
    await _shoot(tester, key, '06-onboarding');
  });

  testWidgets('07 settings', (tester) async {
    final key = await _mount(tester, const SettingsScreen());
    await _shoot(tester, key, '07-settings');
  });

  testWidgets('08 login', (tester) async {
    final key = await _mount(tester, const LoginScreen());
    await _shoot(tester, key, '08-login');
  });

  testWidgets('09 dashboard — dark', (tester) async {
    await _render(tester, const BatteryDashboardScreen(deviceId: _deviceId), 'verify/09-dashboard-dark', theme: JKBMSRTheme.darkTheme);
  });
}
