// Both "which build am I running" surfaces used to print a hardcoded
// "4.17.24 | BUILD 44". A user quoting that in a bug report named a version
// they were not running, so these tests pin the number to the package the
// platform reports.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/widgets/about_modal.dart';
import 'package:jkbmsr_ble/widgets/bms_drawer.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'jkbmsr_ble',
      packageName: 'com.jkbmsr.ble',
      version: '9.9.9',
      buildNumber: '99',
      buildSignature: '',
    );
  });

  testWidgets('drawer footer shows the installed version, not a stale literal',
      (tester) async {
    await _pumpDrawer(tester);

    expect(find.textContaining('9.9.9'), findsOneWidget);
    expect(find.textContaining('BUILD 99'), findsOneWidget);
    expect(find.textContaining('4.17.24'), findsNothing);
  });

  testWidgets('about dialog shows the installed version, not a stale literal',
      (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AboutModal(onClose: _noop)),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('9.9.9'), findsOneWidget);
    expect(find.textContaining('Build 99'), findsOneWidget);
    expect(find.textContaining('4.17.24'), findsNothing);
  });
}

void _noop() {}
