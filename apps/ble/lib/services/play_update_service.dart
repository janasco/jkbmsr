import 'package:in_app_update/in_app_update.dart';

/// What Google Play reports about an available update, expressed in types this
/// app owns so the branch and the UI can be driven by fakes in tests without
/// pulling the plugin's platform channel in.
class PlayUpdateStatus {
  const PlayUpdateStatus({
    required this.availability,
    required this.immediateAllowed,
    required this.flexibleAllowed,
    required this.priority,
    required this.installStatus,
  });

  final PlayUpdateAvailability availability;
  final bool immediateAllowed;
  final bool flexibleAllowed;

  /// In-app update priority (0–5) set on the release in Play Console. 0 is
  /// the default and means "no particular urgency".
  final int priority;
  final PlayInstallStatus installStatus;

  bool get updateAvailable =>
      availability != PlayUpdateAvailability.unavailable;

  /// A high-priority update is treated as blocking and uses Play's immediate
  /// (full-screen) flow. Everything else uses the flexible flow so the user can
  /// keep using the app while the update downloads in the background.
  ///
  /// Play also refuses immediate updates outside certain conditions; if only
  /// the immediate flow is permitted, that is honoured rather than offering a
  /// flexible prompt Play will reject.
  bool get requiresImmediate =>
      updateAvailable && immediateAllowed && (priority >= 4 || !flexibleAllowed);

  bool get isBlocking => updateAvailable && immediateAllowed && priority >= 4;
}

enum PlayUpdateAvailability { unavailable, available, inProgress }

enum PlayInstallStatus {
  unknown,
  pending,
  downloading,
  installing,
  installed,
  failed,
  canceled,
  downloaded,
}

enum PlayUpdateResult { success, userDenied, failed }

/// Seam over the `in_app_update` plugin. The app only ever talks to this
/// interface, so tests substitute a fake and never touch a platform channel.
abstract class PlayUpdateGateway {
  Future<PlayUpdateStatus> checkForUpdate();
  Future<PlayUpdateResult> performImmediateUpdate();
  Future<PlayUpdateResult> startFlexibleUpdate();
  Future<void> completeFlexibleUpdate();
  Stream<PlayInstallStatus> get installStateStream;
}

/// The real gateway: Google Play Core through `in_app_update`.
///
/// Every call is Android/Play-only. On any other platform, or on a copy that
/// did not come from Play, the plugin throws (`MissingPluginException` /
/// `PlatformException`); callers treat that as "no Play update to offer" and
/// never fall back to the sideloaded APK for a Play install.
class InAppUpdateGateway implements PlayUpdateGateway {
  const InAppUpdateGateway();

  @override
  Future<PlayUpdateStatus> checkForUpdate() async {
    final info = await InAppUpdate.checkForUpdate();
    return PlayUpdateStatus(
      availability: _availability(info.updateAvailability),
      immediateAllowed: info.immediateUpdateAllowed,
      flexibleAllowed: info.flexibleUpdateAllowed,
      priority: info.updatePriority,
      installStatus: _installStatus(info.installStatus),
    );
  }

  @override
  Future<PlayUpdateResult> performImmediateUpdate() async =>
      _result(await InAppUpdate.performImmediateUpdate());

  @override
  Future<PlayUpdateResult> startFlexibleUpdate() async =>
      _result(await InAppUpdate.startFlexibleUpdate());

  @override
  Future<void> completeFlexibleUpdate() => InAppUpdate.completeFlexibleUpdate();

  @override
  Stream<PlayInstallStatus> get installStateStream =>
      InAppUpdate.installUpdateListener.map(_installStatus);

  static PlayUpdateAvailability _availability(UpdateAvailability value) {
    switch (value) {
      case UpdateAvailability.updateAvailable:
        return PlayUpdateAvailability.available;
      case UpdateAvailability.developerTriggeredUpdateInProgress:
        return PlayUpdateAvailability.inProgress;
      case UpdateAvailability.updateNotAvailable:
      case UpdateAvailability.unknown:
        return PlayUpdateAvailability.unavailable;
    }
  }

  static PlayInstallStatus _installStatus(InstallStatus value) {
    switch (value) {
      case InstallStatus.unknown:
        return PlayInstallStatus.unknown;
      case InstallStatus.pending:
        return PlayInstallStatus.pending;
      case InstallStatus.downloading:
        return PlayInstallStatus.downloading;
      case InstallStatus.installing:
        return PlayInstallStatus.installing;
      case InstallStatus.installed:
        return PlayInstallStatus.installed;
      case InstallStatus.failed:
        return PlayInstallStatus.failed;
      case InstallStatus.canceled:
        return PlayInstallStatus.canceled;
      case InstallStatus.downloaded:
        return PlayInstallStatus.downloaded;
    }
  }

  static PlayUpdateResult _result(AppUpdateResult value) {
    switch (value) {
      case AppUpdateResult.success:
        return PlayUpdateResult.success;
      case AppUpdateResult.userDeniedUpdate:
        return PlayUpdateResult.userDenied;
      case AppUpdateResult.inAppUpdateFailed:
        return PlayUpdateResult.failed;
    }
  }
}
