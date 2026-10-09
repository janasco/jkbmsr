// The startup update prompt as the user sees it. A Play-installed copy must
// never be offered the direct APK — no "Download" button, no version string
// scraped from our release JSON — while a sideloaded copy still is.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:jkbmsr_pro/services/app_update_service.dart';
import 'package:jkbmsr_pro/services/install_source.dart';
import 'package:jkbmsr_pro/services/play_update_service.dart';
import 'package:jkbmsr_pro/widgets/app_update_prompt.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

class _FakePlayGateway implements PlayUpdateGateway {
  _FakePlayGateway(this.status);

  final PlayUpdateStatus status;
  final _states = StreamController<PlayInstallStatus>.broadcast();

  @override
  Future<PlayUpdateStatus> checkForUpdate() async => status;

  @override
  Future<PlayUpdateResult> startFlexibleUpdate() async =>
      PlayUpdateResult.success;

  @override
  Future<PlayUpdateResult> performImmediateUpdate() async =>
      PlayUpdateResult.success;

  @override
  Future<void> completeFlexibleUpdate() async {}

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
    installedVersionReader: () async => '1.3.36',
  );
  return MaterialApp(
    theme: JKBMSRTheme.darkTheme,
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
  testWidgets('sideload install shows the direct-APK prompt', (tester) async {
    await tester.pumpWidget(_harness(
      () async => 'com.android.packageinstaller',
      httpClient: MockClient(
          (_) async => http.Response('{"version":"1.3.37"}', 200)),
    ));

    await tester.tap(find.text('check'));
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
    expect(find.textContaining('1.3.37'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
  });

  testWidgets('Play install shows the Play prompt and no APK/version text',
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
    expect(find.text('Download'), findsNothing,
        reason: 'a Play user must not be offered a sideloaded APK');
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

  // The About menu's "Check for updates" row drives this same function with
  // `manual: true`. The only behavioural difference is what happens when there
  // is nothing to offer: a manual check says so, a startup check stays silent.
  group('manual check feedback', () {
    testWidgets('an up-to-date manual check says so', (tester) async {
      await tester.pumpWidget(_harness(
        () async => 'com.android.packageinstaller',
        manual: true,
        httpClient: MockClient(
            (_) async => http.Response('{"version":"1.3.36"}', 200)),
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

    testWidgets('a failed sideload check does not claim up to date',
        (tester) async {
      await tester.pumpWidget(_harness(
        () async => 'com.android.packageinstaller',
        manual: true,
        httpClient: MockClient((_) async => http.Response('nope', 503)),
      ));

      await tester.tap(find.text('check'));
      await tester.pumpAndSettle();

      expect(
          find.text(
              "Couldn't check for updates right now. Please try again later."),
          findsOneWidget);
      expect(find.text("You're on the latest version."), findsNothing);
    });

    testWidgets('a manual check with an update still shows the prompt',
        (tester) async {
      await tester.pumpWidget(_harness(
        () async => 'com.android.packageinstaller',
        manual: true,
        httpClient: MockClient(
            (_) async => http.Response('{"version":"1.3.37"}', 200)),
      ));

      await tester.tap(find.text('check'));
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsOneWidget);
      expect(find.text("You're on the latest version."), findsNothing);
    });

    testWidgets('a silent startup check with no update shows nothing',
        (tester) async {
      await tester.pumpWidget(_harness(
        () async => 'com.android.packageinstaller',
        httpClient: MockClient(
            (_) async => http.Response('{"version":"1.3.36"}', 200)),
      ));

      await tester.tap(find.text('check'));
      await tester.pumpAndSettle();

      expect(find.text("You're on the latest version."), findsNothing);
      expect(find.text('Update available'), findsNothing);
    });
  });
}
