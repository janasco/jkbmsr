import 'package:package_info_plus/package_info_plus.dart';

/// How this copy of the app reached the device.
///
/// Contributor is distributed only through Google Play, so the only actionable
/// answer is [play]; anything else means "do nothing about an update".
enum InstallSource {
  /// Android reported Google Play (`com.android.vending`) as the installer.
  play,

  /// Positive evidence of a non-Play install (adb, F-Droid, an OEM store, or a
  /// browser-downloaded APK). Contributor has no self-hosted APK channel, so
  /// nothing is offered.
  sideload,

  /// The installer could not be determined. Nothing is offered, so a Play copy
  /// is never acted on the strength of a missing answer.
  unknown,
}

/// Reads the installer package that created this install.
///
/// The reader is injectable so the Play/non-Play branch is unit-testable
/// without a device or the `package_info_plus` platform channel.
class InstallSourceDetector {
  InstallSourceDetector({Future<String?> Function()? installerStoreReader})
      : _readInstallerStore =
            installerStoreReader ?? _packageInfoInstallerStore;

  final Future<String?> Function() _readInstallerStore;

  /// The single definition of "this is a Play install". Mirrors the helper the
  /// sibling apps use, so all three agree on the boundary.
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
