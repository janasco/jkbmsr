// System back button behaviour.
//
// The guard has to live *inside* the shell route (JKBMSRShellLayout), not in
// MaterialApp.builder: a PopScope above the Navigator has no ModalRoute, so its
// callback never fires and Android just exits the app. These tests drive the
// real platform back message via `tester.binding.handlePopRoute()`.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jkbmsr_pro/app/app.dart';
import 'package:jkbmsr_pro/app/back_intent.dart';
import 'package:jkbmsr_pro/features/settings/settings_screen.dart';
import 'package:jkbmsr_pro/services/api_client.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

GoRouter _shellRouter({String initial = '/dashboard'}) {
  return GoRouter(
    initialLocation: initial,
    routes: [
      ShellRoute(
        builder: (context, state, child) => JKBMSRShellLayout(
          currentRoute: state.uri.path,
          onNavigate: (route) => context.go(route),
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (c, s) =>
                const Scaffold(body: Center(child: Text('DASHBOARD'))),
          ),
          GoRoute(
            path: '/settings',
            builder: (c, s) => const SettingsScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/devices/claim',
        builder: (c, s) => const Scaffold(body: Center(child: Text('CLAIM'))),
      ),
    ],
  );
}

Widget _app(GoRouter router) =>
    MaterialApp.router(theme: JKBMSRTheme.darkTheme, routerConfig: router);

/// The settings screen kicks off plugin-backed loads in initState
/// (package_info_plus at least); stub the channel so the test stays offline
/// and deterministic, and give SharedPreferences an in-memory store.
void _stubPlugins() {
  SharedPreferences.setMockInitialValues({});
  const packageChannel =
      MethodChannel('dev.fluttercommunity.plus/package_info');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(packageChannel, (call) async {
    if (call.method == 'getAll') {
      return <String, dynamic>{
        'appName': 'JK BMS Remote',
        'packageName': 'com.jkbmsr.pro',
        'version': '1.3.25',
        'buildNumber': '57',
        'buildSignature': '',
      };
    }
    return null;
  });
}

http.Response _json(String body, int status) => http.Response(
      body,
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _stubPlugins();
    BackIntentRegistry.reset();
  });

  tearDown(() => BackIntentRegistry.reset());

  testWidgets('first back at a tab root shows the exit toast without popping',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = _shellRouter();
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    expect(find.text('DASHBOARD'), findsOneWidget);
    expect(router.canPop(), isFalse);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Press back again to exit'), findsOneWidget);
    // Still on the dashboard — the app did not exit and no route was popped.
    expect(find.text('DASHBOARD'), findsOneWidget);
    expect(router.canPop(), isFalse);
  });

  testWidgets('a second back within the window exits via SystemNavigator.pop',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final systemPopCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      systemPopCalls.add(call);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final router = _shellRouter();
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(
      systemPopCalls.where((c) => c.method == 'SystemNavigator.pop'),
      isNotEmpty,
      reason: 'the second back within 2s should exit the app',
    );
  });

  testWidgets(
      'back inside a settings category returns to the list without the exit toast',
      (tester) async {
    // Tall enough that the whole category list (incl. the Support group) fits
    // without scrolling, so the tap target is unambiguous.
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    APIClient.configure(
      baseUrl: 'https://test.local',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/devices')) {
          return _json('{"devices":[]}', 200);
        }
        if (request.url.path.endsWith('/sessions')) {
          return _json('{"logins":[]}', 200);
        }
        return _json('{"error":"not found"}', 404);
      }),
    );

    final router = _shellRouter(initial: '/settings');
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    // The settings root shows the category list. 'About' is chosen because
    // its card doesn't touch the app-wide themeController global (which main()
    // initializes in production but not under a bare test pump).
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();

    // Drilled into the About detail.
    expect(find.byTooltip('Back to Settings'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // Back went to the settings list, not out of the app, and no exit toast.
    expect(find.byTooltip('Back to Settings'), findsNothing);
    expect(find.text('Press back again to exit'), findsNothing);
    expect(find.text('About'), findsOneWidget);

    // Drain RequestDeduplication's 5s TTL timer so the binding's end-of-test
    // "no pending timers" invariant holds.
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('back still pops a pushed route above the shell', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = _shellRouter();
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    router.push('/devices/claim');
    await tester.pumpAndSettle();
    expect(find.text('CLAIM'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('CLAIM'), findsNothing);
    expect(find.text('DASHBOARD'), findsOneWidget);
    expect(find.text('Press back again to exit'), findsNothing);
  });
}
