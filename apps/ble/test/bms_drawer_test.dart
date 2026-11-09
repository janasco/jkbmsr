// The drawer is the only place an existing user can discover JK BMS
// Contributor. These tests pin the two things that make the entry useful:
// it asks the platform to open the exact Play listing, and a launch that
// cannot open anything is visible instead of looking successful.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/widgets/bms_drawer.dart';

const _contributorUrl =
    'https://play.google.com/store/apps/details?id=com.jkbmsr.contributor';

Future<GlobalKey<ScaffoldState>> _pumpDrawer(
  WidgetTester tester, {
  required ExternalUriLauncher launchExternal,
}) async {
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
        launchExternal: launchExternal,
      ),
      body: const SizedBox.shrink(),
    ),
  ));

  scaffoldKey.currentState!.openDrawer();
  await tester.pumpAndSettle();
  return scaffoldKey;
}

void main() {
  testWidgets('contributor entry opens the Contributor Play listing',
      (tester) async {
    final requested = <Uri>[];

    await _pumpDrawer(
      tester,
      launchExternal: (uri) async {
        requested.add(uri);
        return true;
      },
    );

    expect(find.text('Help us support your BMS'), findsOneWidget);

    await tester.tap(find.text('Help us support your BMS'));
    await tester.pumpAndSettle();

    expect(requested, hasLength(1));
    expect(requested.single.toString(), _contributorUrl);
    expect(find.byType(SnackBar), findsNothing,
        reason: 'a launch that opened the listing must not claim failure');
  });

  testWidgets('contributor entry shows the URL when the launcher returns false',
      (tester) async {
    await _pumpDrawer(tester, launchExternal: (_) async => false);

    await tester.tap(find.text('Help us support your BMS'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining(_contributorUrl), findsOneWidget);
  });

  testWidgets('contributor entry shows the URL when the launcher throws',
      (tester) async {
    await _pumpDrawer(
      tester,
      launchExternal: (_) async => throw Exception('no Play Store'),
    );

    await tester.tap(find.text('Help us support your BMS'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining(_contributorUrl), findsOneWidget);
  });
}
