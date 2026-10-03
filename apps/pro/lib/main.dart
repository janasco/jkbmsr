import 'dart:async';

import 'package:flutter/material.dart';
import 'app/router.dart';
import 'app/theme_controller.dart';
import 'features/security/cloned_instance_screen.dart';
import 'services/auth_store.dart';
import 'services/biometric_auth_service.dart';
import 'services/biometric_relogin.dart';
import 'services/clone_guard_service.dart';
import 'services/notification_service.dart';
import 'widgets/app_update_prompt.dart';
import 'widgets/shared/design_system/theme.dart';
import 'widgets/shared/design_system/components.dart';

late final ThemeController themeController;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Checked before anything else initializes: a cloned instance shouldn't
  // touch auth storage, Firebase, or the real router at all.
  if (await CloneGuardService.isClonedInstance()) {
    runApp(const ClonedInstanceScreen());
    return;
  }

  themeController = await ThemeController.load();
  await AuthStore.instance.load();
  // Catches the case where the app was killed (not just backgrounded) while
  // past the idle timeout — didChangeAppLifecycleState alone only fires for
  // an app that's still alive to receive the resume callback. If the timeout
  // did lapse (session wiped server-side a while back), go straight for the
  // biometric re-login so a cold launch right after a long absence is one
  // fingerprint instead of re-typing the password.
  final timedOut = await AuthStore.instance.enforceIdleTimeout();
  if (timedOut) {
    await BiometricRelogin.attempt();
  }
  // Firebase Crashlytics was removed: its component failed to register on this
  // AGP 9 / R8 build ("FirebaseCrashlytics component is not present"), which
  // made Firebase.initializeApp() throw and took FCM down with it. Crash
  // reporting can be re-added once that's resolved — push must not depend on it.
  await NotificationService.instance.initializeFirebase();

  // Register/refresh the FCM token on every launch for a signed-in user, so
  // alert push doesn't depend on remembering to toggle a switch in Settings.
  // Best-effort: failures are recorded in NotificationService.lastPushError and
  // surfaced the next time the user touches the notification switches.
  if (NotificationService.instance.isFirebaseReady && await AuthStore.instance.hasToken()) {
    unawaited(NotificationService.instance.getPushToken());
  }

  runApp(const JKBMSRApp());
}

class JKBMSRApp extends StatefulWidget {
  const JKBMSRApp({Key? key}) : super(key: key);

  @override
  State<JKBMSRApp> createState() => _JKBMSRAppState();
}

class _JKBMSRAppState extends State<JKBMSRApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Prompt once per launch if a newer build has been published. Play
    // installs update through Play's in-app flow; sideloaded copies keep the
    // direct-APK prompt (see promptForAppUpdate).
    WidgetsBinding.instance.addPostFrameCallback((_) => promptForAppUpdate(
          contextProvider: () =>
              jkbmsrRouter.routerDelegate.navigatorKey.currentContext,
        ));
    // Foreground pushes don't produce a system notification on their own;
    // surface them as an in-app toast instead.
    NotificationService.instance.onForegroundMessage?.listen((message) {
      final context = jkbmsrRouter.routerDelegate.navigatorKey.currentContext;
      final title = message.notification?.title;
      final body = message.notification?.body;
      if (context == null || (title == null && body == null)) return;
      JKBMSRToast.show(context, [title, body].whereType<String>().join(': '));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // paused: backgrounded. inactive covers the transient iOS state (e.g. a
    // call/notification overlay) too, which is fine — enforceIdleTimeout
    // only actually signs out once idleTimeout has genuinely elapsed.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      AuthStore.instance.recordBackgrounded();
    } else if (state == AppLifecycleState.resumed) {
      _handleResume();
    }
  }

  Future<void> _handleResume() async {
    final timedOut = await AuthStore.instance.enforceIdleTimeout();
    if (timedOut) {
      // Idle timeout wiped the session (deliberate — see enforceIdleTimeout).
      // If the user opted into Biometric Unlock, re-login silently with the
      // finger/face they already approved at enable time; otherwise the
      // router's redirect to /login shows the normal form. Either way there's
      // nothing useful to do past this point this frame.
      await BiometricRelogin.attempt();
      return;
    }

    // If biometric auth is enabled and the user has a valid session,
    // prompt for biometric verification on resume
    final biometricReady = await BiometricAuthService.instance.isReady;
    if (biometricReady && await AuthStore.instance.hasToken()) {
      final authenticated = await BiometricAuthService.instance.authenticate(
        reason: 'Verify your identity to continue',
      );
      if (!authenticated && mounted) {
        // Biometric failed — sign out for security
        await AuthStore.instance.clearUser();
        // GoRouter will redirect to /login via the refreshListenable
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeController,
      builder: (context, mode, _) {
        return MaterialApp.router(
          title: 'JK BMS Remote',
          theme: JKBMSRTheme.lightTheme,
          darkTheme: JKBMSRTheme.darkTheme,
          themeMode: mode,
          routerConfig: jkbmsrRouter,
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
