// The Pro app update branch: a Play-installed copy must update through Google
// Play In-App Updates, and must never be offered the sideloaded APK; a
// sideloaded copy keeps the direct-APK prompt. These drive the real decision
// logic with injected fakes, so no platform channel or network is touched.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:jkbmsr_pro/services/app_update_service.dart';
import 'package:jkbmsr_pro/services/install_source.dart';
import 'package:jkbmsr_pro/services/play_update_service.dart';

class _RecordingPlayGateway implements PlayUpdateGateway {
  _RecordingPlayGateway({
    PlayUpdateStatus? status,
    this.throwOnCheck = false,
  }) : status = status ??
            _playStatus(availability: PlayUpdateAvailability.unavailable);

  final PlayUpdateStatus status;
  final bool throwOnCheck;

  int checkCalls = 0;
  int flexibleCalls = 0;
  int immediateCalls = 0;
  int completeCalls = 0;

  final _installStates = StreamController<PlayInstallStatus>.broadcast();

  @override
  Future<PlayUpdateStatus> checkForUpdate() async {
    checkCalls++;
    if (throwOnCheck) throw StateError('no Play here');
    return status;
  }

  @override
  Future<PlayUpdateResult> startFlexibleUpdate() async {
    flexibleCalls++;
    return PlayUpdateResult.success;
  }

  @override
  Future<PlayUpdateResult> performImmediateUpdate() async {
    immediateCalls++;
    return PlayUpdateResult.success;
  }

  @override
  Future<void> completeFlexibleUpdate() async {
    completeCalls++;
  }

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
  http.Client? httpClient,
  String installedVersion = '1.3.36',
}) =>
    AppUpdateService(
      installSourceDetector:
          InstallSourceDetector(installerStoreReader: installer),
      playUpdateGateway: play ??
          _RecordingPlayGateway(status: _playStatus(availability: PlayUpdateAvailability.unavailable)),
      httpClient: httpClient ??
          MockClient((_) async => throw StateError('network must not be touched')),
      installedVersionReader: () async => installedVersion,
    );

http.Response _json(String body) => http.Response(
      body,
      200,
      headers: {'content-type': 'application/json'},
    );

void main() {
  group('Play-installed copies', () {
    test('use the Play flexible flow, never the website APK', () async {
      final gateway = _RecordingPlayGateway(status: _playStatus(priority: 0));
      var networkCalls = 0;
      final service = _service(
        installer: () async => 'com.android.vending',
        play: gateway,
        httpClient: MockClient((_) async {
          networkCalls++;
          return _json('{"version":"1.3.37"}');
        }),
      );

      final decision = await service.check();

      expect(decision.route, AppUpdateRoute.playFlexible);
      expect(decision.version, isNull,
          reason: 'a Play user must never see a version from our JSON');
      expect(gateway.checkCalls, 1);
      expect(networkCalls, 0,
          reason: 'a Play install must not hit the sideload channel at all');
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

    test('a Play failure never falls back to the website APK', () async {
      final gateway = _RecordingPlayGateway(throwOnCheck: true);
      var networkCalls = 0;
      final service = _service(
        installer: () async => 'com.android.vending',
        play: gateway,
        httpClient: MockClient((_) async {
          networkCalls++;
          return _json('{"version":"1.3.37"}');
        }),
      );

      expect((await service.check()).route, AppUpdateRoute.none);
      expect(networkCalls, 0);
      gateway.dispose();
    });
  });

  group('Sideloaded copies', () {
    test('a newer release-channel version asks for the direct APK', () async {
      final service = _service(
        installer: () async => 'com.android.packageinstaller',
        httpClient: MockClient((_) async => _json('{"version":"1.3.37"}')),
      );

      final decision = await service.check();

      expect(decision.route, AppUpdateRoute.sideloadApk);
      expect(decision.version, '1.3.37');
    });

    test('an up-to-date sideload copy shows nothing', () async {
      final service = _service(
        installer: () async => 'com.android.packageinstaller',
        httpClient: MockClient((_) async => _json('{"version":"1.3.36"}')),
      );

      expect((await service.check()).route, AppUpdateRoute.none);
    });

    test('an unreachable release channel shows nothing', () async {
      final service = _service(
        installer: () async => 'com.android.packageinstaller',
        httpClient: MockClient((_) async => http.Response('nope', 503)),
      );

      expect((await service.check()).route, AppUpdateRoute.none);
    });
  });

  test('an unknown installer touches neither Play nor the release channel',
      () async {
    final gateway = _RecordingPlayGateway(status: _playStatus());
    var networkCalls = 0;
    final service = _service(
      installer: () async => null,
      play: gateway,
      httpClient: MockClient((_) async {
        networkCalls++;
        return _json('{"version":"1.3.37"}');
      }),
    );

    expect((await service.check()).route, AppUpdateRoute.none);
    expect(gateway.checkCalls, 0);
    expect(networkCalls, 0);
    gateway.dispose();
  });

  // A manual "Check for updates" reports its outcome. The distinction that
  // matters: a check that reached the source and found nothing is "up to
  // date"; a check that failed or could not identify the install source is
  // unverifiable — it must never be reported as current.
  group('no-update reason (manual-check feedback)', () {
    test('a Play source that answers "no update" is verifiably up to date',
        () async {
      final gateway = _RecordingPlayGateway(
          status: _playStatus(availability: PlayUpdateAvailability.unavailable));
      final service = _service(
        installer: () async => 'com.android.vending',
        play: gateway,
      );

      final decision = await service.check();

      expect(decision.route, AppUpdateRoute.none);
      expect(decision.noUpdate, AppUpdateNoUpdate.upToDate);
      gateway.dispose();
    });

    test('a Play check that throws is unverifiable, never "up to date"',
        () async {
      final gateway = _RecordingPlayGateway(throwOnCheck: true);
      final service = _service(
        installer: () async => 'com.android.vending',
        play: gateway,
      );

      final decision = await service.check();

      expect(decision.route, AppUpdateRoute.none);
      expect(decision.noUpdate, AppUpdateNoUpdate.unavailable);
      gateway.dispose();
    });

    test('an up-to-date sideload is verifiably current', () async {
      final service = _service(
        installer: () async => 'com.android.packageinstaller',
        httpClient: MockClient((_) async => _json('{"version":"1.3.36"}')),
      );

      expect((await service.check()).noUpdate, AppUpdateNoUpdate.upToDate);
    });

    test('an unreachable release channel is unverifiable, not current',
        () async {
      final service = _service(
        installer: () async => 'com.android.packageinstaller',
        httpClient: MockClient((_) async => http.Response('nope', 503)),
      );

      expect((await service.check()).noUpdate, AppUpdateNoUpdate.unavailable);
    });

    test('a malformed release channel is unverifiable, not current', () async {
      final service = _service(
        installer: () async => 'com.android.packageinstaller',
        httpClient: MockClient((_) async => _json('{}')),
      );

      expect((await service.check()).noUpdate, AppUpdateNoUpdate.unavailable);
    });

    test('an unknown installer is unverifiable', () async {
      final service = _service(installer: () async => null);

      final decision = await service.check();

      expect(decision.route, AppUpdateRoute.none);
      expect(decision.noUpdate, AppUpdateNoUpdate.unavailable);
    });
  });

  test('isNewerVersion compares component-wise and rejects malformed input',
      () {
    expect(AppUpdateService.isNewerVersion('1.3.37', '1.3.36'), isTrue);
    expect(AppUpdateService.isNewerVersion('1.3.36', '1.3.37'), isFalse);
    expect(AppUpdateService.isNewerVersion('1.3.37', '1.3.37'), isFalse);
    expect(AppUpdateService.isNewerVersion('2.0.0', '1.99.99'), isTrue);
    expect(AppUpdateService.isNewerVersion('1.3', '1.3.0'), isFalse);
  });
}
