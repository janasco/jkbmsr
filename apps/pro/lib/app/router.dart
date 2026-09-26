import 'package:go_router/go_router.dart';
import 'app.dart';
import 'navigator_key.dart';
import '../features/auth/login_screen.dart';
import '../features/devices/device_list_screen.dart';
import '../features/devices/device_claim_screen.dart';
import '../features/devices/device_comparison_screen.dart';
import '../features/devices/qr_scan_screen.dart';
import '../features/battery/battery_dashboard_screen.dart';
import '../features/battery/cell_voltages_screen.dart';
import '../features/alerts/alerts_screen.dart';
import '../features/ota/ota_screen.dart';
import '../features/ota/firmware_releases_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/history/telemetry_history_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../services/auth_store.dart';
import '../utils/page_transitions.dart';

/// Cached onboarding state — once true, never re-read from disk.
/// This prevents async timing issues where SharedPreferences reads
/// briefly return stale values during rapid redirect chains.
bool? _cachedOnboardingComplete;

final GoRouter jkbmsrRouter = GoRouter(
  navigatorKey: jkbmsrNavigatorKey,
  initialLocation: '/login',
  refreshListenable: AuthStore.instance,
  redirect: (context, state) async {
    final path = state.uri.path;

    // ── Read onboarding state (cached after first true) ──
    if (_cachedOnboardingComplete != true) {
      _cachedOnboardingComplete = await OnboardingScreen.hasCompleted();
    }
    final onboardingComplete = _cachedOnboardingComplete!;

    // ── ONBOARDING PAGE ──
    if (path == '/onboarding') {
      // Already completed? Send to login (or devices if somehow authed).
      if (onboardingComplete) {
        final isAuth = await AuthStore.instance.hasToken();
        return isAuth ? '/devices' : '/login';
      }
      // Not completed — stay on onboarding. Do NOT check auth here.
      return null;
    }

    // ── LOGIN PAGE ──
    if (path == '/login') {
      // Haven't finished onboarding yet? Go there.
      if (!onboardingComplete) return '/onboarding';
      // Onboarding done + already authenticated? Go to devices.
      final isAuth = await AuthStore.instance.hasToken();
      if (isAuth) return '/devices';
      // Onboarding done, not authed — stay on login.
      return null;
    }

    // ── ALL OTHER PAGES (require both onboarding + auth) ──
    if (!onboardingComplete) return '/onboarding';

    final isAuthenticated = await AuthStore.instance.hasToken();
    if (!isAuthenticated) return '/login';

    return null;
  },
  routes: [
    GoRoute(
      path: '/onboarding',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const OnboardingScreen(),
        transitionsBuilder: JKBMSRPageTransitions.fadeScale,
      ),
    ),
    GoRoute(
      path: '/login',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const LoginScreen(),
        transitionsBuilder: JKBMSRPageTransitions.fadeScale,
      ),
    ),
    GoRoute(
      path: '/devices/claim',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const DeviceClaimScreen(),
        transitionsBuilder: JKBMSRPageTransitions.slideFromBottom,
      ),
    ),
    GoRoute(
      path: '/devices/claim/scan',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const QrScanScreen(),
        transitionsBuilder: JKBMSRPageTransitions.slideFromBottom,
      ),
    ),
    GoRoute(
      path: '/devices/compare',
      pageBuilder: (context, state) {
        // Comma-separated ids: /devices/compare?ids=a,b,c — built by the
        // device list's Compare action when the user multi-selects.
        final idsParam = state.uri.queryParameters['ids'] ?? '';
        final deviceIds = idsParam.split(',').where((s) => s.trim().isNotEmpty).toList();
        return CustomTransitionPage(
          key: state.pageKey,
          child: DeviceComparisonScreen(deviceIds: deviceIds),
          transitionsBuilder: JKBMSRPageTransitions.slideFromRight,
        );
      },
    ),
    ShellRoute(
      builder: (context, state, child) {
        return JKBMSRShellLayout(
          currentRoute: state.uri.path,
          onNavigate: (route) => context.go(route),
          child: child,
        );
      },
      routes: [
        GoRoute(
          path: '/devices',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const DeviceListScreen(),
            transitionsBuilder: JKBMSRPageTransitions.noTransition,
          ),
        ),
        GoRoute(
          path: '/dashboard',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: BatteryDashboardScreen(
              deviceId: state.uri.queryParameters['deviceId'],
            ),
            transitionsBuilder: JKBMSRPageTransitions.slideFromRight,
          ),
        ),
        GoRoute(
          path: '/cells',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: CellVoltagesScreen(
              deviceId: state.uri.queryParameters['deviceId'],
            ),
            transitionsBuilder: JKBMSRPageTransitions.slideFromRight,
          ),
        ),
        GoRoute(
          path: '/alerts',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const AlertsScreen(),
            transitionsBuilder: JKBMSRPageTransitions.noTransition,
          ),
        ),
        GoRoute(
          path: '/ota',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: OTAScreen(
              deviceId: state.uri.queryParameters['deviceId'],
            ),
            transitionsBuilder: JKBMSRPageTransitions.slideFromBottom,
          ),
        ),
        GoRoute(
          path: '/firmware',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: FirmwareReleasesScreen(
              deviceId: state.uri.queryParameters['deviceId'],
            ),
            transitionsBuilder: JKBMSRPageTransitions.slideFromBottom,
          ),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: SettingsScreen(
              deviceId: state.uri.queryParameters['deviceId'],
            ),
            transitionsBuilder: JKBMSRPageTransitions.slideFromBottom,
          ),
        ),
        GoRoute(
          path: '/history',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: TelemetryHistoryScreen(
              deviceId: state.uri.queryParameters['deviceId'],
            ),
            transitionsBuilder: JKBMSRPageTransitions.slideFromBottom,
          ),
        ),
      ],
    ),
  ],
);
