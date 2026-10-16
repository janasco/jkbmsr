// The update prompt as the user sees it in JK BMS Bluetooth. A Play-installed
// copy must never be offered the in-app APK download (no "Software Update"
// modal, no version scraped from our release JSON), while a sideloaded copy
// still is; and a normal-priority Play release downloads flexibly and then
// asks to restart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:jkbmsr_ble/services/app_update_service.dart';
import 'package:jkbmsr_ble/services/install_source.dart';
import 'package:jkbmsr_ble/services/play_update_service.dart';
import 'package:jkbmsr_ble/widgets/app_update_prompt.dart';
import 'package:jkbmsr_ble/widgets/software_update_modal.dart';

class _FakePlayGateway implements PlayUpdateGateway {
  _FakePlayGateway(this.status);

  final PlayUpdateStatus status;
  final _states = StreamController<PlayInstallStatus>.broadcast();

  int completeCalls = 0;

  void emit(PlayInstallStatus status) => _states.add(status);

  @override
  Future<PlayUpdateStatus> checkForUpdate() async => status;

  @override
  Future<PlayUpdateResult> startFlexibleUpdate() async =>
      PlayUpdateResult.success;

  @override
  Future<PlayUpdateResult> performImmediateUpdate() async =>
      PlayUpdateResult.success;

  @override
  Future<void> completeFlexibleUpdate() async {
    completeCalls++;
  }

  @override
  Stream<PlayInstallStatus> get installStateStream => _states.stream;

  void dispose() => _states.close();
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

Widget _harness(
  Future<String?> Function() installer, {
  PlayUpdateGateway? play,
  http.Client? httpClient,
  bool manual = false,
}) {
  final service = AppUpdateService(
    installSourceDetector: InstallSourceDetector(installerStoreReader: installer),
    playUpdateGateway: play,
    httpClient: httpClient ?? MockClient((_) async => http.Response('{}', 503)),
    installedVersionReader: () async => '4.17.27',
  );
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => promptForAppUpdate(
              contextProvider: () => context,
              service: service,
              manual: manual,
            ),
            child: const Text('check'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('sideload install opens the existing direct-APK modal',
      (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'JK BMS Bluetooth',
      packageName: 'com.jkbmsr.ble',
      version: '4.17.27',
      buildNumber: '47',
      buildSignature: '',
    );

    await tester.pumpWidget(_harness(
      () async => 'com.android.packageinstaller',
      httpClient: MockClient(
          (_) async => http.Response('{"version":"4.17.28"}', 200)),
    ));

    await tester.tap(find.text('check'));
    await tester.pumpAndSettle();

    expect(find.byType(SoftwareUpdateModal), findsOneWidget,
        reason: 'a sideloaded copy keeps the existing direct-APK path');
  });

  testWidgets('Play install shows the Play prompt, not the in-app APK',
      (tester) async {
    final gateway = _FakePlayGateway(_playStatus(priority: 0));
    addTearDown(gateway.dispose);

    await tester.pumpWidget(_harness(
      () async => 'com.android.vending',
      play: gateway,
      httpClient: MockClient(
          (_) async => http.Response('{"version":"9.9.9"}', 200)),
    ));

    await tester.tap(find.text('check'));
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
    expect(find.byType(SoftwareUpdateModal), findsNothing,
        reason: 'a Play user must not reach the in-app APK modal');
    expect(find.textContaining('9.9.9'), findsNothing,
        reason: 'our JSON version must never reach a Play user');
  });

  testWidgets('a blocking Play update is immediate and has no Later',
      (tester) async {
    final gateway = _FakePlayGateway(_playStatus(priority: 5));
    addTearDown(gateway.dispose);

    await tester.pumpWidget(_harness(
      () async => 'com.android.vending',
      play: gateway,
    ));

    await tester.tap(find.text('check'));
    await tester.pumpAndSettle();

    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
    expect(find.text('Later'), findsNothing);
  });

  testWidgets(
      'a flexible Play update downloads, then prompts to restart and completes',
      (tester) async {
    final gateway = _FakePlayGateway(_playStatus(priority: 0));
    addTearDown(gateway.dispose);

    await tester.pumpWidget(_harness(
      () async => 'com.android.vending',
      play: gateway,
    ));

    await tester.tap(find.text('check'));
    await tester.pumpAndSettle();

    // Accept the flexible prompt: the download starts in the background.
    await tester.tap(find.text('Update'));
    await tester.pump();
    await tester.pump();

    // Play reports the download finished.
    gateway.emit(PlayInstallStatus.downloaded);
    await tester.pumpAndSettle();

    expect(find.text('Update ready'), findsOneWidget);
    expect(find.text('Restart'), findsOneWidget);

    await tester.tap(find.text('Restart'));
    await tester.pumpAndSettle();

    expect(gateway.completeCalls, 1,
        reason: 'the restart must hand off to Play to apply the update');
  });

  // The drawer's "Software Update" row drives this same function with
  // `manual: true`. The only behavioural difference is what happens when there
  // is nothing to offer: a manual check says so, a startup check stays silent.
  group('manual check feedback', () {
    testWidgets('an up-to-date manual check says so', (tester) async {
      await tester.pumpWidget(_harness(
        () async => 'com.android.packageinstaller',
        manual: true,
        httpClient: MockClient(
            (_) async => http.Response('{"version":"4.17.27"}', 200)),
      ));

      await tester.tap(find.text('check'));
      await tester.pumpAndSettle();

      expect(find.text("You're on the latest version."), findsOneWidget);
      expect(find.text('Update available'), findsNothing);
    });

    testWidgets('an unverifiable manual check does not claim up to date',
        (tester) async {
      await tester.pumpWidget(_harness(
        () async => null,
        manual: true,
      ));

      await tester.tap(find.text('check'));
      await tester.pumpAndSettle();

      expect(
          find.text(
              "Couldn't check for updates right now. Please try again later."),
          findsOneWidget);
      expect(find.text("You're on the latest version."), findsNothing);
    });

    testWidgets('a silent startup check with no update shows nothing',
        (tester) async {
      await tester.pumpWidget(_harness(
        () async => 'com.android.packageinstaller',
        httpClient: MockClient(
            (_) async => http.Response('{"version":"4.17.27"}', 200)),
      ));

      await tester.tap(find.text('check'));
      await tester.pumpAndSettle();

      expect(find.text("You're on the latest version."), findsNothing);
      expect(find.text('Update available'), findsNothing);
    });
  });
}
