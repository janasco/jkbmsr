import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'install_source.dart';
import 'play_update_service.dart';

/// What the app should do about an update, if anything.
enum AppUpdateRoute {
  none,

  /// A sideloaded copy: download the latest APK from the release channel.
  /// Play policy does not permit this for a Play-distributed copy.
  sideloadApk,

  /// A Play-installed copy: Play's flexible update (normal, non-blocking).
  playFlexible,

  /// A Play-installed copy: Play's immediate update (blocking).
  playImmediate,
}

/// The outcome of one update check, already branched on how the app was
/// installed.
class AppUpdateDecision {
  const AppUpdateDecision(this.route, {this.version, this.blocking = false});

  static const none = AppUpdateDecision(AppUpdateRoute.none);

  final AppUpdateRoute route;

  /// Marketing version from the release channel. **Sideload only** — a Play
  /// user's version story belongs to Play, so no string from our JSON is ever
  /// shown to them.
  final String? version;

  /// True when a Play release is marked high-priority and the immediate flow
  /// should not offer a "Later".
  final bool blocking;
}

/// Decides how an update should be offered, branching on how the app was
/// installed:
///
///   * **Play-installed** → Google Play In-App Updates. Never a website, never
///     an APK, never a raw version from our JSON.
///   * **sideloaded** → the existing direct-APK prompt, unchanged.
///   * **unknown** → nothing, so an unproven install is never sent to the
///     sideload path.
///
/// Every dependency is injectable so the branch is unit-testable.
class AppUpdateService {
  AppUpdateService({
    InstallSourceDetector? installSourceDetector,
    PlayUpdateGateway? playUpdateGateway,
    http.Client? httpClient,
    Future<String> Function()? installedVersionReader,
  })  : _installSource = installSourceDetector ?? InstallSourceDetector(),
        _play = playUpdateGateway ?? const InAppUpdateGateway(),
        _http = httpClient ?? http.Client(),
        _installedVersion = installedVersionReader ?? _packageVersion;

  static const String latestJsonUrl =
      'https://api.jkbmsr.com/mobile/latest.json';
  static const String downloadUrl = 'https://api.jkbmsr.com/mobile/latest.apk';

  final InstallSourceDetector _installSource;
  final PlayUpdateGateway _play;
  final http.Client _http;
  final Future<String> Function() _installedVersion;

  Future<AppUpdateDecision> check() async {
    final source = await _installSource.detect();
    switch (source) {
      case InstallSource.play:
        return _checkViaPlay();
      case InstallSource.sideload:
        return _checkViaSideloadApk();
      case InstallSource.unknown:
        return AppUpdateDecision.none;
    }
  }

  Future<AppUpdateDecision> _checkViaPlay() async {
    try {
      final status = await _play.checkForUpdate();
      if (!status.updateAvailable) return AppUpdateDecision.none;
      if (status.requiresImmediate) {
        return AppUpdateDecision(
          AppUpdateRoute.playImmediate,
          blocking: status.isBlocking,
        );
      }
      return const AppUpdateDecision(AppUpdateRoute.playFlexible);
    } catch (_) {
      // Play unavailable, or not actually a Play build. A Play-installed copy
      // is never redirected to the website APK as a fallback — doing so would
      // be exactly the policy violation this branch exists to prevent.
      return AppUpdateDecision.none;
    }
  }

  /// Sideload-only: check the release channel the direct APK is published to.
  /// Never reached for a Play install.
  Future<AppUpdateDecision> _checkViaSideloadApk() async {
    try {
      final installed = await _installedVersion();
      final response = await _http
          .get(Uri.parse(latestJsonUrl))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return AppUpdateDecision.none;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final latest = body['version'] as String?;
      if (latest == null || latest.isEmpty) return AppUpdateDecision.none;
      if (!isNewerVersion(latest, installed)) return AppUpdateDecision.none;
      return AppUpdateDecision(AppUpdateRoute.sideloadApk, version: latest);
    } catch (_) {
      return AppUpdateDecision.none;
    }
  }

  // --- Play update actions, driven by the UI after a decision ---------------

  Future<PlayUpdateResult> startFlexibleUpdate() => _play.startFlexibleUpdate();

  Future<void> completeFlexibleUpdate() => _play.completeFlexibleUpdate();

  Future<PlayUpdateResult> performImmediateUpdate() =>
      _play.performImmediateUpdate();

  Stream<PlayInstallStatus> get playInstallStateStream =>
      _play.installStateStream;

  /// Component-wise semver compare ("1.3.37" > "1.3.36"). Any malformed
  /// version never claims an update exists.
  static bool isNewerVersion(String latest, String installed) {
    final a = latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final b = installed.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static Future<String> _packageVersion() async =>
      (await PackageInfo.fromPlatform()).version;
}
