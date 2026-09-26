import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../widgets/shared/design_system/components.dart';

/// Handles a system back intent that the current screen wants to consume
/// without letting the Navigator pop (e.g. leaving a settings category detail
/// back to the settings list). Return true when the intent was handled; return
/// false to let normal navigation continue.
typedef BackIntentHandler = bool Function();

/// A single-slot registry for the innermost "back means go back one step
/// inside this screen" handler.
///
/// The shell route owns the only [PopScope] (see [JKBMSRBackGuard]) because a
/// PopScope above the Navigator — e.g. in `MaterialApp.builder` — has no
/// `ModalRoute`, never receives the callback, and lets the Android back button
/// exit the app. Screens that maintain their own back stack as internal state
/// register here while they're drilled in and clear it on the way out. Only one
/// screen can be in that state at a time, so a single slot is enough; a stale
/// handler would otherwise swallow back on an unrelated screen.
class BackIntentRegistry {
  BackIntentRegistry._();

  static BackIntentHandler? _handler;

  /// Installs [handler] as the active inner back handler, replacing any
  /// previous one.
  static void register(BackIntentHandler handler) {
    _handler = handler;
  }

  /// Removes the active inner back handler, if any.
  static void clear() {
    _handler = null;
  }

  /// Runs the registered handler, if any. Returns true when it consumed the
  /// intent.
  static bool invoke() {
    final handler = _handler;
    if (handler == null) return false;
    return handler();
  }

  /// Clears any registered handler — for tests, so state can't leak between
  /// cases.
  @visibleForTesting
  static void reset() => _handler = null;
}

/// The owner of the Android system back button for the whole shell.
///
/// It must live *inside* the shell route (see [JKBMSRShellLayout]) — a PopScope
/// in `MaterialApp.builder` sits above the Navigator, has no ModalRoute, and
/// never fires.
///
/// Handling order:
///
///  1. An inner handler registered via [BackIntentRegistry] (screen-local back
///     stacks such as the settings category detail).
///  2. A pushed route above the shell (`GoRouter.canPop()`), which we pop
///     ourselves — e.g. `/devices/claim`.
///  3. Otherwise confirm-to-exit: a first back shows a toast, a second press
///     within [_exitPressWindow] actually exits the app.
///
/// A [PopScope] alone is *not* enough with a plain `ShellRoute`. Flutter's
/// `handlePopRoute` only consults a Navigator's `maybePop` (and therefore any
/// route's PopScope) when that Navigator reports `canPop()`. At a tab root
/// neither the root Navigator nor the shell's nested Navigator can pop, so
/// go_router's `RouterDelegate.popRoute()` returns false and the framework
/// falls straight through to `SystemNavigator.pop()` without ever reaching the
/// PopScope. Registering as a [WidgetsBindingObserver] closes that gap: the
/// router's back-button dispatcher runs first and returns false in exactly this
/// case, then [didPopRoute] gets its turn before the exit fallback. The
/// PopScope is kept as well for Flutter/go_router versions that do route the
/// callback through `maybePop`; the two paths are mutually exclusive because
/// whichever one handles the event makes `handlePopRoute` stop.
class JKBMSRBackGuard extends StatefulWidget {
  final Widget child;

  const JKBMSRBackGuard({Key? key, required this.child}) : super(key: key);

  @override
  State<JKBMSRBackGuard> createState() => _JKBMSRBackGuardState();
}

class _JKBMSRBackGuardState extends State<JKBMSRBackGuard>
    with WidgetsBindingObserver {
  static const Duration _exitPressWindow = Duration(seconds: 2);
  DateTime? _lastBackPressAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The back path that actually fires on this go_router/ShellRoute setup — see
  /// the class doc. Returning true marks the event handled so the framework
  /// doesn't also exit the app.
  @override
  Future<bool> didPopRoute() async => _handleBack();

  /// Shared by both interception paths. Returns true when handled.
  bool _handleBack() {
    // (a) A screen-local back stack (settings category detail) gets first
    // refusal — it isn't a route, so the router can't see it.
    if (BackIntentRegistry.invoke()) return true;

    // (b) A pushed route above the shell (e.g. /devices/claim).
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return true;
    }

    // (c) At the root of the in-app stack — confirm before exiting.
    final now = DateTime.now();
    if (_lastBackPressAt != null &&
        now.difference(_lastBackPressAt!) < _exitPressWindow) {
      SystemNavigator.pop();
      return true;
    }
    _lastBackPressAt = now;
    JKBMSRToast.show(context, 'Press back again to exit');
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: widget.child,
    );
  }
}
