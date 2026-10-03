import 'package:package_info_plus/package_info_plus.dart';

/// How this copy of the app reached the device.
///
/// The distinction is load-bearing for updates: a Google Play copy must update
/// through Play (Play policy forbids sending a Play user to a sideloaded APK),
/// while a copy installed from `api.jkbmsr.com` legitimately keeps the direct
/// APK prompt.
enum InstallSource {
  /// Android reported Google Play (`com.android.vending`) as the installer.
  play,

  /// Positive evidence of a non-Play install: adb, F-Droid, an OEM store, or
  /// a browser-downloaded APK. The direct-APK self-update path is legitimate
  /// here.
  sideload,

  /// The installer could not be determined (iOS, or a failed read). Nothing
  /// update-related is offered, so a Play copy is never sent down the sideload
  /// path on the strength of a missing answer.
  unknown,
}

/// Reads the installer package that created this install.
///
/// The reader is injectable so the Play/sideload branch is unit-testable
/// without a device or the `package_info_plus` platform channel.
class InstallSourceDetector {
  InstallSourceDetector({Future<String?> Function()? installerStoreReader})
      : _readInstallerStore =
            installerStoreReader ?? _packageInfoInstallerStore;

  final Future<String?> Function() _readInstallerStore;

  /// The single definition of "this is a Play install" for Pro. Mirrors the
  /// helper the companion BLE app uses, so both apps agree on the boundary.
  static bool isPlayInstaller(String? installerStore) =>
      installerStore == 'com.android.vending';

  Future<InstallSource> detect() async {
    try {
      final store = await _readInstallerStore();
      if (isPlayInstaller(store)) return InstallSource.play;
      if (store == null || store.isEmpty) return InstallSource.unknown;
      return InstallSource.sideload;
    } catch (_) {
      return InstallSource.unknown;
    }
  }

  static Future<String?> _packageInfoInstallerStore() async =>
      (await PackageInfo.fromPlatform()).installerStore;
}
