import '../app/navigator_key.dart';
import '../widgets/shared/design_system/components.dart';
import 'auth_store.dart';

/// Fires when APIClient sees a 401 "Unauthorized" from an already-signed-in
/// call — i.e. the server has stopped honoring this device's token (it
/// expired, or was invalidated by a sign-out-everywhere elsewhere). Without
/// this, a dead token used to fail silently: periodic dashboard polling
/// swallows errors so the UI just froze on stale data with zero indication,
/// and the only way back in was force-closing the app.
///
/// Clearing AuthStore here is enough to send the user back to /login on its
/// own — GoRouter's `refreshListenable: AuthStore.instance` re-evaluates its
/// redirect the moment notifyListeners() fires, no app restart needed.
class SessionExpiryHandler {
  static bool _handling = false;

  static Future<void> handle() async {
    if (_handling) return;
    _handling = true;
    try {
      final hadSession = await AuthStore.instance.hasToken();
      if (!hadSession) return;
      await AuthStore.instance.clearUser();

      final context = jkbmsrNavigatorKey.currentContext;
      if (context != null) {
        JKBMSRToast.show(
          context,
          "You've been signed out due to inactivity. Please log in again.",
          isError: true,
        );
      }
    } finally {
      _handling = false;
    }
  }
}
