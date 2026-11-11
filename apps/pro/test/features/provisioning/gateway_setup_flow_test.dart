// The setup flow: three steps, each gated on the thing it needs, and the zone
// list pinned to the format the gateway can actually apply.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jkbmsr_pro/features/provisioning/discovered_gateway.dart';
import 'package:jkbmsr_pro/features/provisioning/gateway_provisioner.dart';
import 'package:jkbmsr_pro/features/provisioning/gateway_setup_flow.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

const _gateway = DiscoveredGateway(
  id: 'AA:BB:CC:DD:EE:01',
  name: 'JKBMSR-Setup-4A21',
  rssi: -64,
);

Widget _host(Widget child) {
  return MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    builder: (context, inner) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: inner!,
    ),
    home: child,
  );
}

Future<void> _enterCode(WidgetTester tester, String code) async {
  await tester.enterText(find.byType(TextField).first, code);
  await tester.pump();
}

void main() {
  testWidgets('the code step will not continue without six digits',
      (tester) async {
    await tester.pumpWidget(_host(const GatewaySetupFlow(gateway: _gateway)));

    FilledButton button() =>
        tester.widget<FilledButton>(find.byType(FilledButton));

    expect(button().onPressed, isNull);

    await _enterCode(tester, '41830');
    expect(button().onPressed, isNull);

    await _enterCode(tester, '418302');
    expect(button().onPressed, isNotNull);

    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Which Wi-Fi should it use?'), findsOneWidget);
  });

  testWidgets('the network step needs a Wi-Fi name', (tester) async {
    await tester.pumpWidget(_host(const GatewaySetupFlow(gateway: _gateway)));
    await _enterCode(tester, '418302');
    await tester.tap(find.text('Continue'));
    await tester.pump();

    FilledButton button() =>
        tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button().onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, 'HouseWiFi');
    await tester.pump();
    expect(button().onPressed, isNotNull);
  });

  testWidgets('a successful setup reports the gateway as added', (tester) async {
    final provisioner = FakeGatewayProvisioner();

    await tester.pumpWidget(_host(GatewaySetupFlow(
      gateway: _gateway,
      provisioner: provisioner,
      claimTokenProvider: () async => 'aa.bb.cc',
    )));

    await _enterCode(tester, '418302');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'HouseWiFi');
    await tester.pump();
    await tester.tap(find.text('Start setup'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Gateway added'), findsOneWidget);
    expect(provisioner.lastRequest?.setupCode, '418302');
    expect(provisioner.lastRequest?.ssid, 'HouseWiFi');
    expect(provisioner.lastRequest?.timeZone, isNotEmpty);
  });

  testWidgets('a provisioner that fails says so and keeps the settings',
      (tester) async {
    final provisioner = FakeGatewayProvisioner(
      stages: const [ProvisioningStage.saving],
      error: StateError('The gateway stopped responding.'),
    );

    await tester.pumpWidget(_host(GatewaySetupFlow(
      gateway: _gateway,
      provisioner: provisioner,
      claimTokenProvider: () async => 'aa.bb.cc',
    )));

    await _enterCode(tester, '418302');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'HouseWiFi');
    await tester.pump();
    await tester.tap(find.text('Start setup'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('The gateway stopped responding.'), findsOneWidget);
    expect(find.text('Change settings'), findsOneWidget);
  });

  testWidgets('the default provisioner refuses rather than faking success',
      (tester) async {
    await tester.pumpWidget(_host(GatewaySetupFlow(
      gateway: _gateway,
      claimTokenProvider: () async => 'aa.bb.cc',
    )));

    await _enterCode(tester, '418302');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'HouseWiFi');
    await tester.pump();
    await tester.tap(find.text('Start setup'));
    await tester.pump();
    await tester.pump();

    // The radio is not wired in this build. Claiming success here would be the
    // worst outcome: the owner would mount a gateway that was never configured.
    expect(find.textContaining('not available in this build'), findsOneWidget);
    expect(find.textContaining('Gateway added'), findsNothing);
  });

  test('every offered zone is a POSIX string the gateway accepts', () {
    final allowed = RegExp(r'^[A-Za-z0-9+\-:,./<>]+$');
    for (final zone in GatewayTimeZone.all) {
      expect(zone.posix, isNotEmpty, reason: zone.label);
      expect(zone.posix.length, lessThanOrEqualTo(48), reason: zone.posix);
      expect(allowed.hasMatch(zone.posix), isTrue, reason: zone.posix);
      // The firmware rule: a slash is legal only inside a DST rule time, so it
      // can only appear after a comma. "Asia/Manila" is the case this catches,
      // and libc would silently ignore it rather than reject it.
      if (zone.posix.contains('/')) {
        expect(zone.posix.contains(','), isTrue, reason: zone.posix);
      }
      expect(RegExp(r'^[A-Za-z]{2,}').hasMatch(zone.posix), isTrue,
          reason: 'a POSIX zone starts with a name: ${zone.posix}');
    }
  });

  testWidgets('a claim token that cannot be minted is said out loud',
      (tester) async {
    await tester.pumpWidget(_host(GatewaySetupFlow(
      gateway: _gateway,
      provisioner: FakeGatewayProvisioner(),
      claimTokenProvider: () async =>
          throw StateError('Please verify your email address before claiming a device.'),
    )));

    await _enterCode(tester, '418302');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'HouseWiFi');
    await tester.pump();
    await tester.tap(find.text('Start setup'));
    await tester.pump();
    await tester.pump();

    // The server's own reason reaches the user: "verify your email" is
    // actionable, and "setup failed" would not be.
    expect(
      find.textContaining('Please verify your email address'),
      findsOneWidget,
    );
    expect(find.textContaining('Gateway added'), findsNothing);
  });
}
