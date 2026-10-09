import 'package:google_sign_in/google_sign_in.dart';

/// Wraps native "Sign in with Google" and returns the ID token that
/// POST /v1/user/google verifies.
///
/// `_serverClientId` must stay equal to jkbmsr-web's NEXT_PUBLIC_GOOGLE_CLIENT_ID
/// (and the API worker's GOOGLE_CLIENT_ID), since the backend checks the
/// token's `aud` claim against that single value. Passing it as
/// `serverClientId` here makes the native flow request a token audienced to
/// the existing web client, so no backend change is needed. The Android/iOS
/// OAuth clients registered separately in Google Cloud Console exist only so
/// Google trusts this app's identity (package + signing cert on Android,
/// bundle ID on iOS) when running the native sign-in flow.
class GoogleAuthService {
  static const String _serverClientId =
      '702996273044-omolsbpj15k3t6nm325gllnmhppej974.apps.googleusercontent.com';

  static final GoogleSignIn _instance = GoogleSignIn(
    scopes: const ['email'],
    serverClientId: _serverClientId,
  );

  /// Runs the native sign-in flow. Returns null if the user cancelled.
  ///
  /// signOut() first clears this plugin's cached session (not the device's
  /// Google account, and not the OAuth grant — signOut(), not disconnect())
  /// so signIn() can't silently reuse it: without this, Android's Google
  /// Sign-In SDK skips the account picker entirely and logs straight into
  /// whichever account was used last, which is surprising on a
  /// multi-account device and makes switching accounts impossible.
  static Future<String?> signInAndGetIdToken() async {
    await _instance.signOut();
    final account = await _instance.signIn();
    if (account == null) {
      return null;
    }
    final auth = await account.authentication;
    return auth.idToken;
  }
}
