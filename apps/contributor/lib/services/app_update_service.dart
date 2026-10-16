import 'install_source.dart';
import 'play_update_service.dart';

/// What the app should do about an update, if anything.
///
/// Contributor is Play-only: there is deliberately no `sideloadApk` route,
/// because there is no self-hosted APK channel (unlike the BLE app) and Play
/// policy forbids pointing a Play user at one anyway.
enum AppUpdateRoute {
  /// Nothing to do: the install is not from Play, or Play reports no update.
  none,

  /// A Play-installed copy: Play's flexible update (normal, non-blocking).
  playFlexible,

  /// A Play-installed copy: Play's immediate update (blocking).
  playImmediate,
}

/// The outcome of one update check.
class AppUpdateDecision {
  const AppUpdateDecision(this.route, {this.blocking = false});

  final AppUpdateRoute route;

  /// True when a Play release is marked high-priority and the immediate flow
  /// should not offer a "Later".
  final bool blocking;
}

/// Decides how an update should be offered.
///
///   * **Play-installed** → Google Play In-App Updates.
///   * **anything else** → nothing. Contributor never offers an APK, so a
///     non-Play install (or an unreadable installer package) is left alone.
///
/// Every dependency is injectable so the branch is unit-testable.
class AppUpdateService {
  AppUpdateService({
    InstallSourceDetector? installSourceDetector,
    PlayUpdateGateway? playUpdateGateway,
  })  : _installSource = installSourceDetector ?? InstallSourceDetector(),
        _play = playUpdateGateway ?? const InAppUpdateGateway();

  final InstallSourceDetector _installSource;
  final PlayUpdateGateway _play;

  Future<AppUpdateDecision> check() async {
    final source = await _installSource.detect();
    // Only a confirmed Play install has anything to offer. A sideloaded or
    // unknown install does nothing rather than reaching for an APK.
    if (source != InstallSource.play) {
      return const AppUpdateDecision(AppUpdateRoute.none);
    }
    return _checkViaPlay();
  }

  Future<AppUpdateDecision> _checkViaPlay() async {
    try {
      final status = await _play.checkForUpdate();
      if (!status.updateAvailable) {
        return const AppUpdateDecision(AppUpdateRoute.none);
      }
      if (status.requiresImmediate) {
        return AppUpdateDecision(
          AppUpdateRoute.playImmediate,
          blocking: status.isBlocking,
        );
      }
      return const AppUpdateDecision(AppUpdateRoute.playFlexible);
    } catch (_) {
      // Play unavailable, or not actually a Play build. There is no sideload
      // fallback for this app; nothing is offered.
      return const AppUpdateDecision(AppUpdateRoute.none);
    }
  }

  // --- Play update actions, driven by the UI after a decision ---------------

  Future<PlayUpdateResult> startFlexibleUpdate() => _play.startFlexibleUpdate();

  Future<void> completeFlexibleUpdate() => _play.completeFlexibleUpdate();

  Future<PlayUpdateResult> performImmediateUpdate() =>
      _play.performImmediateUpdate();

  Stream<PlayInstallStatus> get playInstallStateStream =>
      _play.installStateStream;
}
