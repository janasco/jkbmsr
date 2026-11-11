// The scan screen: the radar, the floating gateway cards, and the states that
// are not "found something".
//
// The radar respects MediaQuery.disableAnimations, which is both the
// accessibility contract and what lets these tests finish: a repeating animation
// makes pumpAndSettle wait out its ten-minute default.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jkbmsr_pro/features/provisioning/discovered_gateway.dart';
import 'package:jkbmsr_pro/features/provisioning/gateway_scan_screen.dart';
import 'package:jkbmsr_pro/features/provisioning/gateway_scan_source.dart';
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

void main() {
  testWidgets('a detected gateway becomes a tile that opens the setup flow',
      (tester) async {
    final source = FakeGatewayScanSource(initial: const [_gateway]);

    await tester.pumpWidget(
      _host(GatewayScanScreen(
        scanSource: source,
        emptyAfter: const Duration(seconds: 30),
      )),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Gateway 4A21'), findsOneWidget);
    expect(find.text('Tap to set up'), findsOneWidget);
    expect(find.text('Gateway found'), findsOneWidget);

    await tester.tap(find.text('Gateway 4A21'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Enter the setup code'), findsOneWidget);
  });

  testWidgets('a build without the radio says so instead of an empty room',
      (tester) async {
    await tester.pumpWidget(_host(const GatewayScanScreen()));
    await tester.pump();
    await tester.pump();

    // An empty list would read as "no hardware nearby" and send the owner
    // looking at a gateway that is fine.
    expect(find.text('Bluetooth setup is not ready'), findsOneWidget);
    expect(find.text('No gateway found'), findsNothing);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a scan that finds nothing stops and offers a rescan',
      (tester) async {
    final source = FakeGatewayScanSource();

    await tester.pumpWidget(
      _host(GatewayScanScreen(
        scanSource: source,
        emptyAfter: const Duration(milliseconds: 50),
      )),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();

    expect(find.text('No gateway found'), findsOneWidget);
    expect(source.stopCalls, greaterThan(0));

    // The radar pushes the rescan button below an 800x600 test surface, and a
    // tap at a point outside the viewport silently lands nowhere.
    await tester.ensureVisible(find.text('Scan again'));
    await tester.pump();
    await tester.tap(find.text('Scan again'));
    // pump, not pumpAndSettle: this screen's empty-state timer is 50 ms, and a
    // settle would advance past it and put the test back in the state it just
    // left.
    await tester.pump();
    await tester.pump();
    expect(source.startCalls, 2);
    expect(find.text('Looking for a gateway'), findsOneWidget);
  });

  testWidgets('a blocked permission is named, not swallowed', (tester) async {
    final source = FakeGatewayScanSource(failure: ScanFailure.permissionDenied);

    await tester.pumpWidget(
      _host(GatewayScanScreen(scanSource: source)),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
        'JK BMS Remote needs Bluetooth permission to find your gateway. Allow it when Android asks.',
      ),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('leaving the screen stops the scan', (tester) async {
    final source = FakeGatewayScanSource(initial: const [_gateway]);

    await tester.pumpWidget(
      _host(GatewayScanScreen(
        scanSource: source,
        emptyAfter: const Duration(seconds: 30),
      )),
    );
    await tester.pump();
    await tester.pump();

    await tester.pumpWidget(_host(const SizedBox.shrink()));
    await tester.pump();

    expect(source.stopCalls, greaterThan(0));
    // An injected source is owned by the caller, so the screen must not close it.
    expect(source.disposed, isFalse);
  });

  test('signal bars are coarse on purpose', () {
    const near = DiscoveredGateway(id: 'a', name: 'JKBMSR-Setup-1111', rssi: -50);
    const far = DiscoveredGateway(id: 'b', name: 'JKBMSR-Setup-2222', rssi: -95);
    expect(near.signalBars, 3);
    expect(far.signalBars, 1);
    expect(far.shortCode, '2222');
  });
}
