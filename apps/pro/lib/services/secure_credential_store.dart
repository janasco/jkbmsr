import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the long-lived biometric *unlock token* — created server-side by
/// `POST /user/biometric/enable` — in the OS keychain (iOS) / Android
/// Keystore-backed encrypted storage. The account **password is never stored**;
/// the token is exchanged for a fresh session at `/user/biometric/login` after
/// the OS biometric prompt.
///
/// Populated only while "Biometric Unlock" is enabled; cleared on disable,
/// manual sign-out, password change (server revokes it), or account deletion.
/// Deliberately *not* cleared by [AuthStore.clearUser] — the idle-timeout path
/// relies on it surviving so it can mint a fresh session.
class SecureCredentialStore {
  static const String _keyUnlockToken = 'jkbmsr.biometricUnlockToken';

  // flutter_secure_storage 11 encrypts on Android by default (AES-GCM with
  // RSA-OAEP key wrapping), so the old encryptedSharedPreferences flag has no
  // replacement to name: passing no options is the strong path now.
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static final SecureCredentialStore instance = SecureCredentialStore._();
  SecureCredentialStore._();

  Future<void> saveToken(String token) async {
    await _storage.write(key: _keyUnlockToken, value: token);
  }

  Future<String?> readToken() async {
    final token = await _storage.read(key: _keyUnlockToken);
    return (token == null || token.isEmpty) ? null : token;
  }

  Future<void> clear() async {
    await _storage.delete(key: _keyUnlockToken);
  }
}
