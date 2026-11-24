// The failure half of the version labels: when the platform cannot report its
// package, both surfaces must say "unknown". Falling back to a literal would
// put a wrong version in a bug report, which is the defect the labels exist to
// remove.
//
// No PackageInfo mock is installed in this file, so `fromPlatform` reaches the
// (unregistered) platform channel and throws — the same shape as a build where
// the plugin cannot answer.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/widgets/about_modal.dart';
import 'package:jkbmsr_ble/widgets/bms_drawer.dart';

Future<void> _pumpDrawer(WidgetTester tester) async {
  tester.view.physicalSize = const Size(500, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final scaffoldKey = GlobalKey<ScaffoldState>();
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(
      key: scaffoldKey,
      drawer: BmsDrawer(
        onNavigateToDevices: () {},
        onOpenSoftwareUpdate: () {},
        onOpenSupport: () {},
        onOpenAbout: () {},
      ),
      body: const SizedBox.shrink(),
    ),
  ));

  scaffoldKey.currentState!.openDrawer();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('drawer footer says unknown when the package cannot be read',
      (tester) async {
    await _pumpDrawer(tester);

    expect(find.textContaining('unknown'), findsOneWidget);
    expect(find.textContaining('4.17.24'), findsNothing);
  });

  testWidgets('about dialog says unknown when the package cannot be read',
      (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AboutModal(onClose: _noop)),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('unknown'), findsOneWidget);
    expect(find.textContaining('4.17.24'), findsNothing);
  });
}

void _noop() {}
