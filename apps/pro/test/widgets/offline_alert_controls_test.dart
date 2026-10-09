// Widget coverage for the owner-side offline-alert controls on the per-gateway
// dashboard: both directions of the acknowledgement, the mute toggle, the
// self-suppression for a healthy gateway, and the disabled-while-in-flight
// behaviour.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jkbmsr_pro/features/battery/widgets/offline_alert_controls.dart';
import 'package:jkbmsr_pro/models/device_wifi_target.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/components.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

const _ackKey = ValueKey('offline-alert-acknowledge');
const _reenableKey = ValueKey('offline-alert-reenable');
const _muteKey = ValueKey('offline-alert-mute');

Widget _wrap(
  WifiAlertState alert, {
  bool busy = false,
  VoidCallback? onAcknowledge,
  VoidCallback? onReenable,
  ValueChanged<bool>? onToggleMute,
}) {
  return MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    home: Scaffold(
      body: OfflineAlertControls(
        alert: alert,
        busy: busy,
        onAcknowledge: onAcknowledge ?? () {},
        onReenable: onReenable ?? () {},
        onToggleMute: onToggleMute ?? (_) {},
      ),
    ),
  );
}

void main() {
  testWidgets('active, un-acknowledged outage offers Acknowledge, not Re-enable', (tester) async {
    var acknowledged = 0;
    await tester.pumpWidget(_wrap(
      WifiAlertState(active: true, count: 2),
      onAcknowledge: () => acknowledged++,
    ));

    expect(find.text('Gateway offline alert'), findsOneWidget);
    expect(find.textContaining("alerted you 2 times"), findsOneWidget);
    expect(find.byKey(_ackKey), findsOneWidget);
    expect(find.byKey(_reenableKey), findsNothing);

    await tester.tap(find.byKey(_ackKey));
    expect(acknowledged, 1);
  });

  testWidgets('acknowledged outage offers Re-enable, not Acknowledge', (tester) async {
    var reenabled = 0;
    await tester.pumpWidget(_wrap(
      WifiAlertState(active: true, count: 2, acknowledgedAt: '2026-10-09 12:40:00'),
      onReenable: () => reenabled++,
    ));

    expect(find.text('Offline alerts acknowledged'), findsOneWidget);
    expect(find.byKey(_ackKey), findsNothing);
    expect(find.byKey(_reenableKey), findsOneWidget);

    await tester.tap(find.byKey(_reenableKey));
    expect(reenabled, 1);
  });

  testWidgets('muted-only gateway shows the toggle in its on state, no buttons', (tester) async {
    await tester.pumpWidget(_wrap(const WifiAlertState(active: false, count: 0, muted: true)));

    expect(find.text('Offline alerts muted'), findsOneWidget);
    expect(find.byKey(_ackKey), findsNothing);
    expect(find.byKey(_reenableKey), findsNothing);

    final tile = tester.widget<SwitchListTile>(find.byKey(_muteKey));
    expect(tile.value, isTrue);
  });

  testWidgets('toggling the switch reports the requested value', (tester) async {
    bool? requested;
    await tester.pumpWidget(_wrap(
      WifiAlertState(active: true, count: 1),
      onToggleMute: (value) => requested = value,
    ));

    await tester.tap(find.byKey(_muteKey));
    await tester.pump();
    expect(requested, isTrue);
  });

  testWidgets('healthy gateway renders nothing at all', (tester) async {
    await tester.pumpWidget(_wrap(const WifiAlertState(active: false, count: 0)));

    expect(find.byType(JKBMSRAlertBanner), findsNothing);
    expect(find.byKey(_ackKey), findsNothing);
    expect(find.byKey(_muteKey), findsNothing);
  });

  testWidgets('unknown state renders nothing (shouldShow false)', (tester) async {
    expect(OfflineAlertControls.shouldShow(null), isFalse);
    expect(
      OfflineAlertControls.shouldShow(const WifiAlertState(active: false, count: 0)),
      isFalse,
    );
    expect(
      OfflineAlertControls.shouldShow(
          const WifiAlertState(active: false, count: 0, muted: true)),
      isTrue,
    );
  });

  testWidgets('in-flight disables the action button and the mute switch', (tester) async {
    await tester.pumpWidget(_wrap(
      WifiAlertState(active: true, count: 1),
      busy: true,
    ));

    expect(tester.widget<ElevatedButton>(find.byKey(_ackKey)).onPressed, isNull);
    expect(tester.widget<SwitchListTile>(find.byKey(_muteKey)).onChanged, isNull);
  });

  testWidgets('action buttons meet the 48dp minimum tap target', (tester) async {
    await tester.pumpWidget(_wrap(WifiAlertState(active: true, count: 1)));
    expect(tester.getSize(find.byKey(_ackKey)).height, greaterThanOrEqualTo(48));

    await tester.pumpWidget(_wrap(
      WifiAlertState(active: true, count: 1, acknowledgedAt: '2026-10-09 12:40:00'),
    ));
    expect(tester.getSize(find.byKey(_reenableKey)).height, greaterThanOrEqualTo(48));
  });
}
