import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'biometric_auth_service.dart';
import 'secure_credential_store.dart';

/// Orchestrates the "quick unlock after a session ends" flow: when the stored
/// JWT is gone (idle timeout elapsed, app killed while backgrounded, or the
/// server rejected it after its 1h expiry), but the user has Biometric Unlock
/// enabled and a stored unlock token, verify identity with the OS biometric
/// prompt and then exchange the token for a fresh session.
///
/// Returns true only on a full success (biometrics recognized AND the token
/// exchange succeeded). On failure the caller falls through to the normal
/// "/login" redirect — [AuthStore.instance] notifies the router.
class BiometricRelogin {
  /// Human-readable reason for the most recent failed [attempt], for callers
  /// to surface (null after a success). Lets the login screen show the real
  /// cause instead of a generic message.
  static String? lastError;

  static Future<bool> attempt({
    String reason = 'Verify your identity to continue',
  }) async {
    lastError = null;
    // Not opted in / unsupported device — nothing to try.
    if (!await BiometricAuthService.instance.isReady) {
      lastError = 'Biometric unlock is not enabled on this device.';
      return false;
    }

    final unlockToken = await SecureCredentialStore.instance.readToken();
    if (unlockToken == null) {
      lastError = 'No saved biometric token. Turn Biometric Unlock off and on again.';
      return false;
    }

    final authenticated = await BiometricAuthService.instance.authenticate(reason: reason);
    if (!authenticated) {
      lastError = 'Biometric verification was cancelled or failed.';
      return false;
    }

    try {
      // biometricLogin persists the fresh session via AuthStore.
      await APIClient.instance.biometricLogin(unlockToken);
      return true;
    } on Exception catch (error) {
      // Two kinds of failure:
      //  - The token was revoked (password change, sign-out-all, disable) or
      //    expired. Keeping it would just re-trigger the same failed attempt
      //    on every resume, so drop it.
      //  - The device is just offline. Keep the token and fall through to the
      //    login screen this once.
      lastError = error.toString();
      if (!_isNetworkError(error)) {
        await SecureCredentialStore.instance.clear();
        lastError = '$lastError (token cleared — re-enable Biometric Unlock)';
      }
      return false;
    }
  }

  static bool _isNetworkError(Exception error) {
    return error is SocketException ||
        error is HttpException ||
        error is TimeoutException ||
        error is http.ClientException;
  }
}
