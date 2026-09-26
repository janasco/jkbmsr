import 'dart:io';
import 'package:flutter/services.dart';

/// Detects whether this process is running inside an Android OS-level
/// "Dual Apps" / "Clone Apps" / "App Twin" secondary user profile (a
/// built-in OEM feature on Xiaomi, Samsung, OnePlus, etc.) rather than the
/// app's real, primary install — see MainActivity.kt for the native check.
///
/// JKBMSR already auto-signs-out idle/dead sessions (SessionExpiryHandler),
/// so a cloned second copy doesn't add any real capability — it only
/// fragments push notifications and sessions across two installs the user
/// didn't mean to have. main.dart refuses to run at all when this is true.
class CloneGuardService {
  static const _channel = MethodChannel('jkbmsr/security');

  static Future<bool> isClonedInstance() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isClonedProfile');
      return result ?? false;
    } catch (_) {
      // Fail open — a channel/platform hiccup must never block a
      // legitimate primary install from starting.
      return false;
    }
  }
}
