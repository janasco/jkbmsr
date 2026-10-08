// Parameter editor: while live telemetry is flowing but the settings frame has
// not arrived, the form must show skeleton value bars rather than a wall of
// "—". The schema (labels and groups) is known immediately, so the real labels
// stay and only the values are placeholders. The amber "waiting" banner stays
// too, because it is the actionable hint.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/models/bms_models.dart';
import 'package:jkbmsr_ble/screens/bms_parameters_screen.dart';
import 'package:jkbmsr_ble/services/ble_service.dart';
import 'package:jkbmsr_ble/widgets/motion_kit.dart';

import 'support/fake_flutter_blue_plus.dart';

void main() {
  setUp(() {
    installFakeFlutterBluePlus();
    BleBmsService().debugResetConnectionState();
  });
  tearDown(() => BleBmsService().debugResetConnectionState());

  testWidgets('parameters form shows skeleton fields until the settings frame arrives',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Live JK-BMS telemetry, but no settings values in the snapshot yet.
    BleBmsService().debugSetConnectionState(
      isConnected: true,
      brand: BmsBrand.jkbms,
      hasLiveData: true,
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BmsParametersScreen(embedded: true)),
    ));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byType(JkSkeleton), findsWidgets,
        reason: 'with no settings values yet, parameter values are placeholders');
    // A real schema label is still present, so it reads as pending, not blank.
    expect(find.text('Cell Undervoltage Protection'), findsOneWidget);
    expect(
      find.text('Waiting for the settings frame — tap Sync to request it now.'),
      findsOneWidget,
    );
  });
}
