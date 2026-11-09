// The Pack status card is compact, multi-line and sits at the top of the
// dashboard. It must survive the OS's largest common text scale on a narrow
// phone without an overflow stripe, and its one control must reach Alerts.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/features/alerts/pack_check.dart';
import 'package:jkbmsr_pro/features/battery/pack_status.dart';
import 'package:jkbmsr_pro/features/battery/widgets/pack_status_card.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

/// Registers the bundled faces so the overflow check measures the typeface
/// that actually ships, not the widget-test placeholder metrics.
Future<void> _loadBundledFonts() async {
  Future<void> load(String family, List<String> faces) async {
    final loader = FontLoader(family);
    for (final face in faces) {
      final bytes = File('assets/fonts/$face').readAsBytesSync();
      loader.addFont(
        Future.value(ByteData.sublistView(Uint8List.fromList(bytes))),
      );
    }
    await loader.load();
  }

  await load('IBMPlexSans', [
    'IBMPlexSans-Regular.ttf',
    'IBMPlexSans-Medium.ttf',
    'IBMPlexSans-SemiBold.ttf',
    'IBMPlexSans-Bold.ttf',
  ]);
  await load('IBMPlexMono', [
    'IBMPlexMono-Regular.ttf',
    'IBMPlexMono-Medium.ttf',
    'IBMPlexMono-Bold.ttf',
  ]);
}

PackStatusInput _input({
  bool isOwner = true,
  String? ownerEmail,
  String? firmwareVersion = '0.9.10',
  String? latestFirmwareVersion = '0.9.10',
  bool updateAvailable = false,
  bool hasTelemetry = true,
  bool? bmsLinkUp = true,
  int? secondsSinceLastTelemetry = 12,
}) {
  return PackStatusInput(
    isOwner: isOwner,
    ownerEmail: ownerEmail,
    firmwareVersion: firmwareVersion,
    latestFirmwareVersion: latestFirmwareVersion,
    updateAvailable: updateAvailable,
    pack: PackCheckInput(
      deviceName: 'Warehouse Backup Bank — North Wing Array',
      hasTelemetry: hasTelemetry,
      cellVoltages:
          hasTelemetry ? const [3.300, 3.302, 3.304, 3.306] : const [],
      temperature1C: hasTelemetry ? 22.0 : 0,
      temperature2C: hasTelemetry ? 22.4 : 0,
      socPercent: hasTelemetry ? 84 : null,
      currentAmps: hasTelemetry ? -12 : null,
      fullCapacityAh: hasTelemetry ? 100 : null,
      bmsLinkUp: bmsLinkUp,
      secondsSinceLastTelemetry: secondsSinceLastTelemetry,
      expectedIntervalSeconds: 60,
    ),
  );
}

Widget _wrap(Widget child, {double textScale = 1.0}) {
  return MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    ),
  );
}

void _phoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadBundledFonts);

  testWidgets('lays out every line and the health sentence at textScale 2.0',
      (tester) async {
    _phoneViewport(tester);
    final summary = buildPackStatus(_input(
      isOwner: false,
      ownerEmail: 'long-owner-address-for-a-shared-gateway@example.com',
      firmwareVersion: null,
      latestFirmwareVersion: null,
      hasTelemetry: false,
      bmsLinkUp: null,
      secondsSinceLastTelemetry: null,
    ));

    await tester.pumpWidget(_wrap(
      PackStatusCard(summary: summary, onViewDetails: () {}),
      textScale: 2.0,
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Pack status'), findsOneWidget);
    expect(find.text('Gateway claimed'), findsOneWidget);
    expect(find.text('Reporting telemetry'), findsOneWidget);
    expect(find.text('Battery link'), findsOneWidget);
    expect(find.text('Firmware up to date'), findsOneWidget);
    expect(
      find.text('Not enough data to check the pack yet.'),
      findsOneWidget,
    );
    expect(find.text('View pack check'), findsOneWidget);
  });

  testWidgets('lays out a findings state at textScale 2.0', (tester) async {
    _phoneViewport(tester);
    final summary = buildPackStatus(_input(updateAvailable: true));

    await tester.pumpWidget(_wrap(
      PackStatusCard(summary: summary, onViewDetails: () {}),
      textScale: 2.0,
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Update available — 0.9.10'), findsOneWidget);
    expect(find.text('The readings that could be checked look normal.'),
        findsOneWidget);
  });

  testWidgets('the detail link calls back once', (tester) async {
    _phoneViewport(tester);
    var taps = 0;

    await tester.pumpWidget(_wrap(
      PackStatusCard(
        summary: buildPackStatus(_input()),
        onViewDetails: () => taps++,
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('View pack check'));
    await tester.pump();

    expect(taps, 1);
  });
}
