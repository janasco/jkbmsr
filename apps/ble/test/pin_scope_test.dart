// PIN scope: the local control PIN authorises BMS writes, and nothing else.
//
// Play rejected a release as "Missing sign in details" because a reviewer
// reached a PIN prompt while merely browsing. These tests pin the corrected
// rule so it cannot silently regress:
//   * with no BMS connected, no screen asks for a PIN and the app is fully
//     browsable (the reviewer's fresh-install case);
//   * viewing screens and the app's own preferences (theme, PIN change)
//     never prompt;
//   * the prompt appears only on the write path, with a BMS connected, and a
//     write is never attempted until the PIN verifies.
//
// The connected cases use BleBmsService.debugSetConnectionState, which is
// test-only: there is no BLE stack on the Dart VM, so without it the write
// path (and the gate in front of it) is unreachable.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/main.dart';
import 'package:jkbmsr_ble/models/bms_models.dart';
import 'package:jkbmsr_ble/screens/bms_parameters_screen.dart';
import 'package:jkbmsr_ble/screens/control_screen.dart';
import 'package:jkbmsr_ble/screens/controls_screen.dart';
import 'package:jkbmsr_ble/screens/settings_screen.dart';
import 'package:jkbmsr_ble/services/ble_service.dart';
import 'package:jkbmsr_ble/widgets/auth_pin_dialog.dart';

import 'support/fake_flutter_blue_plus.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(body: child),
  );
}

/// Types [pin] into the open PIN dialog and presses UNLOCK, then pumps enough
/// frames for the async verification to resolve. Returns nothing; callers
/// assert on the visible outcome. (No pumpAndSettle: the ambient background
/// loops forever, so settling would time out.)
Future<void> _submitPin(WidgetTester tester, String pin) async {
  final field = find.descendant(
    of: find.byType(AuthPinDialog),
    matching: find.byType(TextField),
  );
  expect(field, findsOneWidget, reason: 'the PIN dialog should expose one field');
  await tester.enterText(field, pin);
  await tester.pump();

  final unlock = find.descendant(
    of: find.byType(AuthPinDialog),
    matching: find.text('UNLOCK'),
  );
  expect(unlock, findsOneWidget);
  await tester.tap(unlock);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    installFakeFlutterBluePlus();
    BleBmsService().debugResetConnectionState();
  });
  tearDown(() => BleBmsService().debugResetConnectionState());

  group('no BMS connected — nothing to authorise, so no PIN anywhere', () {
    testWidgets('Settings: theme and control-PIN change never prompt for a PIN',
        (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(const SettingsScreen()));
      await tester.pump(const Duration(milliseconds: 400));

      // Entering the screen does not prompt.
      expect(find.byType(AuthPinDialog), findsNothing);

      // The PIN field is editable without any unlock step...
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isNot(false),
          reason: 'changing the app PIN must not require the control PIN');
      await tester.enterText(find.byType(TextField), '4321');
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '4321');

      // ...and the old padlock affordance is gone.
      expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
      expect(find.byIcon(Icons.lock_open_rounded), findsNothing);

      // Saving is reachable directly; empty input fails validation (a snack
      // bar), never a PIN prompt.
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('SAVE'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AuthPinDialog), findsNothing);
      expect(find.text('PIN must be at least 4 characters.'), findsOneWidget);
    });

    testWidgets('Control: no BMS means no prompt, no switches, disabled unlock',
        (tester) async {
      await tester.pumpWidget(_wrap(const ControlScreen()));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AuthPinDialog), findsNothing);
      expect(find.text('NO BMS CONNECTED'), findsOneWidget);
      // Nothing to write to, so no switches are offered and no PIN is asked.
      expect(find.text('Charge Switch'), findsNothing);

      final unlock = find.widgetWithText(ElevatedButton, 'UNLOCK');
      expect(unlock, findsOneWidget);
      expect(tester.widget<ElevatedButton>(unlock).onPressed, isNull,
          reason: 'the unlock control must be inert without a BMS');
    });

    testWidgets('BMS parameters: unsupported view, no edit lock, no PIN',
        (tester) async {
      await tester.pumpWidget(_wrap(const BmsParametersScreen()));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('No BMS connected'), findsOneWidget);
      expect(find.byType(AuthPinDialog), findsNothing);
      expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
    });

    testWidgets('Controls: no BMS shows an honest empty state, never a PIN',
        (tester) async {
      await tester.pumpWidget(_wrap(const ControlsScreen()));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Connect to a BMS to use controls'), findsOneWidget);
      // Nothing to control, so no section selector and no prompt.
      expect(find.text('SWITCHES'), findsNothing);
      expect(find.text('PARAMETERS'), findsNothing);
      expect(find.byType(AuthPinDialog), findsNothing);
    });

    testWidgets('fresh install: app settings open from the drawer with no PIN',
        (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const JkbmsrBleApp());
      await tester.pump(const Duration(milliseconds: 600));

      final start = find.text('START SCANNING');
      if (start.evaluate().isNotEmpty) {
        await tester.tap(start);
        await tester.pump(const Duration(milliseconds: 600));
      }

      // Settings is no longer a bottom-nav tab: it moved into the drawer.
      expect(find.text('SETTINGS'), findsNothing,
          reason: 'the Settings tab was replaced by Controls');

      await tester.tap(find.byIcon(Icons.menu_rounded));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      final appSettings = find.text('App settings');
      expect(appSettings, findsOneWidget);
      await tester.tap(appSettings);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      expect(find.text('CONTROL PIN'), findsOneWidget);
      expect(find.byType(AuthPinDialog), findsNothing,
          reason: 'opening app settings must not prompt for the control PIN');
    });
  });

  group('BMS connected — the PIN is demanded at the write, not on entry', () {
    setUp(() {
      BleBmsService().debugSetConnectionState(
        isConnected: true,
        brand: BmsBrand.jkbms,
        hasLiveData: true,
      );
    });

    testWidgets('Control: entering the screen is free; toggling requires the PIN',
        (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(const ControlScreen()));
      await tester.pump(const Duration(milliseconds: 400));

      // Viewing a connected BMS does not prompt...
      expect(find.byType(AuthPinDialog), findsNothing);
      expect(find.text('Charge Switch'), findsOneWidget);

      // ...but attempting the write does.
      await tester.tap(find.text('Charge Switch'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byType(AuthPinDialog), findsOneWidget);
      expect(find.text('Unlock Controls'), findsOneWidget);

      // A wrong PIN keeps the gate shut and the dialog open.
      await _submitPin(tester, '0000');
      expect(find.byType(AuthPinDialog), findsOneWidget);
      expect(find.text('Incorrect PIN. Try again.'), findsOneWidget);

      // The correct PIN lets the write proceed.
      await _submitPin(tester, '1234');
      expect(find.byType(AuthPinDialog), findsNothing);
    });

    testWidgets('BMS parameters: the PIN is verified before the value editor',
        (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(const BmsParametersScreen()));
      await tester.pump(const Duration(milliseconds: 400));

      // Viewing live parameters does not prompt.
      expect(find.byType(AuthPinDialog), findsNothing);
      expect(find.byIcon(Icons.lock_outline_rounded), findsWidgets);

      // Tapping an edit lock is the write path and does prompt.
      await tester.tap(find.byIcon(Icons.lock_outline_rounded).first);
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byType(AuthPinDialog), findsOneWidget);
      expect(find.text('Unlock Parameter Editing'), findsOneWidget);

      // Verifying opens that row's editor (an unlocked padlock appears).
      await _submitPin(tester, '1234');
      expect(find.byType(AuthPinDialog), findsNothing);
      expect(find.byIcon(Icons.lock_open_rounded), findsWidgets);
    });

    testWidgets(
        'Controls: section switch is free; each section gates only its writes',
        (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(const ControlsScreen()));
      await tester.pump(const Duration(milliseconds: 400));

      // The merged surface opens on the switches section; browsing is free.
      expect(find.byType(AuthPinDialog), findsNothing);
      expect(find.text('SWITCHES'), findsOneWidget);
      expect(find.text('PARAMETERS'), findsOneWidget);
      expect(find.text('Charge Switch'), findsOneWidget);

      // Switching to the parameters section does not prompt either.
      await tester.tap(find.text('PARAMETERS'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AuthPinDialog), findsNothing);
      expect(find.byIcon(Icons.lock_outline_rounded), findsWidgets);

      // The parameters write path still does.
      await tester.tap(find.byIcon(Icons.lock_outline_rounded).first);
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byType(AuthPinDialog), findsOneWidget);
      expect(find.text('Unlock Parameter Editing'), findsOneWidget);
    });
  });
}
