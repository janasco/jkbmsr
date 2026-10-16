// The Contributor update prompt as the user sees it. Contributor is Play-only:
// a Play-installed copy gets Play In-App Updates (a flexible prompt that
// downloads then asks to restart, or Play's immediate flow), and any other
// install shows nothing at all.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jkbmsr_contributor/services/app_update_service.dart';
import 'package:jkbmsr_contributor/services/install_source.dart';
import 'package:jkbmsr_contributor/services/play_update_service.dart';
import 'package:jkbmsr_contributor/widgets/app_update_prompt.dart';

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
}) {
  final service = AppUpdateService(
    installSourceDetector: InstallSourceDetector(installerStoreReader: installer),
    playUpdateGateway: play,
  );
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => promptForAppUpdate(
              contextProvider: () => context,
              service: service,
            ),
            child: const Text('check'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a non-Play install shows nothing', (tester) async {
    final gateway = _FakePlayGateway(_playStatus(priority: 5));
    addTearDown(gateway.dispose);

    await tester.pumpWidget(_harness(
      () async => 'com.android.packageinstaller',
      play: gateway,
    ));

    await tester.tap(find.text('check'));
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsNothing);
    expect(find.text('Update required'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(gateway.completeCalls, 0);
  });

  testWidgets('a Play install shows the Play prompt', (tester) async {
    final gateway = _FakePlayGateway(_playStatus(priority: 0));
    addTearDown(gateway.dispose);

    await tester.pumpWidget(_harness(
      () async => 'com.android.vending',
      play: gateway,
    ));

    await tester.tap(find.text('check'));
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
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

    await tester.tap(find.text('Update'));
    await tester.pump();
    await tester.pump();

    gateway.emit(PlayInstallStatus.downloaded);
    await tester.pumpAndSettle();

    expect(find.text('Update ready'), findsOneWidget);
    expect(find.text('Restart'), findsOneWidget);

    await tester.tap(find.text('Restart'));
    await tester.pumpAndSettle();

    expect(gateway.completeCalls, 1,
        reason: 'the restart must hand off to Play to apply the update');
  });
}
