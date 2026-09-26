import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Biometric authentication service for quick re-authentication after
/// session timeout. Wraps the local_auth package with JKBMSR-specific
/// preferences and error handling.
class BiometricAuthService {
  static const String _prefsKeyEnabled = 'jkbmsr.biometricEnabled';
  static const String _prefsKeyAvailable = 'jkbmsr.biometricAvailable';

  final LocalAuthentication _localAuth = LocalAuthentication();

  static final BiometricAuthService instance = BiometricAuthService._();
  BiometricAuthService._();

  /// Whether the user has explicitly enabled biometric unlock.
  Future<bool> get isEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyEnabled) ?? false;
  }

  /// Whether the device supports biometric auth (fingerprint, face, etc.).
  Future<bool> get isAvailable async {
    try {
      final available = await _localAuth.canCheckBiometrics;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKeyAvailable, available);
      return available;
    } catch (_) {
      return false;
    }
  }

  /// Get the list of biometric types available on this device.
  Future<List<BiometricType>> get availableBiometrics async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Enable biometric unlock preference.
  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyEnabled, enabled);
  }

  /// Attempt biometric authentication.
  /// Returns true if the user authenticated successfully.
  /// Returns false if they cancelled or biometrics aren't available.
  Future<bool> authenticate({String? reason}) async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: reason ?? 'Authenticate to access JKBMSR',
        options: const AuthenticationOptions(
          stickyAuth: true,
          // Biometrics only. With this false, Android shows the device
          // PIN/pattern/passcode screen (biometrics as one option inside it),
          // which is why users saw a PIN prompt even with biometric unlock on.
          // Callers gate on isReady (available && enabled) first, so a device
          // with no enrolled biometrics never reaches here.
          biometricOnly: true,
          useErrorDialogs: true,
        ),
      );
      return authenticated;
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Check if biometric auth is both available and enabled by the user.
  Future<bool> get isReady async {
    return await isAvailable && await isEnabled;
  }
}
