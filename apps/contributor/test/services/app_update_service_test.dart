// The Contributor update branch: only a Play-installed copy has anything to
// offer (Play In-App Updates); any other install does nothing, because there is
// no self-hosted APK channel. These drive the real decision logic with injected
// fakes, so no platform channel or network is touched.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:jkbmsr_contributor/services/app_update_service.dart';
import 'package:jkbmsr_contributor/services/install_source.dart';
import 'package:jkbmsr_contributor/services/play_update_service.dart';

class _RecordingPlayGateway implements PlayUpdateGateway {
  _RecordingPlayGateway({
    PlayUpdateStatus? status,
    this.throwOnCheck = false,
  }) : status = status ??
            _playStatus(availability: PlayUpdateAvailability.unavailable);

  final PlayUpdateStatus status;
  final bool throwOnCheck;

  int checkCalls = 0;

  final _installStates = StreamController<PlayInstallStatus>.broadcast();

  @override
  Future<PlayUpdateStatus> checkForUpdate() async {
    checkCalls++;
    if (throwOnCheck) throw StateError('no Play here');
    return status;
  }

  @override
  Future<PlayUpdateResult> startFlexibleUpdate() async =>
      PlayUpdateResult.success;

  @override
  Future<PlayUpdateResult> performImmediateUpdate() async =>
      PlayUpdateResult.success;

  @override
  Future<void> completeFlexibleUpdate() async {}

  @override
  Stream<PlayInstallStatus> get installStateStream => _installStates.stream;

  void dispose() => _installStates.close();
}

PlayUpdateStatus _playStatus({
  PlayUpdateAvailability availability = PlayUpdateAvailability.available,
  bool immediate = true,
  bool flexible = true,
  int priority = 0,
}) =>
    PlayUpdateStatus(
      availability: availability,
      immediateAllowed: immediate,
      flexibleAllowed: flexible,
      priority: priority,
      installStatus: PlayInstallStatus.unknown,
    );

AppUpdateService _service({
  required Future<String?> Function() installer,
  PlayUpdateGateway? play,
}) =>
    AppUpdateService(
      installSourceDetector:
          InstallSourceDetector(installerStoreReader: installer),
      playUpdateGateway: play ??
          _RecordingPlayGateway(
              status: _playStatus(
                  availability: PlayUpdateAvailability.unavailable)),
    );

void main() {
  group('Play-installed copies', () {
    test('use the flexible flow for a normal-priority release', () async {
      final gateway = _RecordingPlayGateway(status: _playStatus(priority: 0));
      final service = _service(
        installer: () async => 'com.android.vending',
        play: gateway,
      );

      final decision = await service.check();

      expect(decision.route, AppUpdateRoute.playFlexible);
      expect(gateway.checkCalls, 1);
      gateway.dispose();
    });

    test('a high-priority release uses the blocking immediate flow', () async {
      final gateway = _RecordingPlayGateway(status: _playStatus(priority: 5));
      final service = _service(
        installer: () async => 'com.android.vending',
        play: gateway,
      );

      final decision = await service.check();

      expect(decision.route, AppUpdateRoute.playImmediate);
      expect(decision.blocking, isTrue);
      gateway.dispose();
    });

    test('an immediate-only release is immediate but not blocking', () async {
      final gateway = _RecordingPlayGateway(
          status: _playStatus(flexible: false, priority: 0));
      final service = _service(
        installer: () async => 'com.android.vending',
        play: gateway,
      );

      final decision = await service.check();

      expect(decision.route, AppUpdateRoute.playImmediate);
      expect(decision.blocking, isFalse);
      gateway.dispose();
    });

    test('no Play update means no prompt', () async {
      final gateway = _RecordingPlayGateway(
          status: _playStatus(availability: PlayUpdateAvailability.unavailable));
      final service = _service(
        installer: () async => 'com.android.vending',
        play: gateway,
      );

      expect((await service.check()).route, AppUpdateRoute.none);
      gateway.dispose();
    });

    test('a Play failure offers nothing (no APK fallback exists)', () async {
      final gateway = _RecordingPlayGateway(throwOnCheck: true);
      final service = _service(
        installer: () async => 'com.android.vending',
        play: gateway,
      );

      expect((await service.check()).route, AppUpdateRoute.none);
      gateway.dispose();
    });
  });

  group('Non-Play copies', () {
    test('a sideloaded install does nothing and never asks Play', () async {
      final gateway = _RecordingPlayGateway(status: _playStatus(priority: 5));
      final service = _service(
        installer: () async => 'com.android.packageinstaller',
        play: gateway,
      );

      final decision = await service.check();

      expect(decision.route, AppUpdateRoute.none,
          reason: 'there is no contributor APK endpoint to offer');
      expect(gateway.checkCalls, 0);
      gateway.dispose();
    });

    test('an unknown installer does nothing and never asks Play', () async {
      final gateway = _RecordingPlayGateway(status: _playStatus(priority: 5));
      final service = _service(
        installer: () async => null,
        play: gateway,
      );

      expect((await service.check()).route, AppUpdateRoute.none);
      expect(gateway.checkCalls, 0);
      gateway.dispose();
    });

    test('an unreadable installer does nothing and never asks Play', () async {
      final gateway = _RecordingPlayGateway(status: _playStatus(priority: 5));
      final service = _service(
        installer: () async => throw StateError('no package info'),
        play: gateway,
      );

      expect((await service.check()).route, AppUpdateRoute.none);
      expect(gateway.checkCalls, 0);
      gateway.dispose();
    });
  });
}
