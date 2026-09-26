// Accessibility device pass: the gateway-list group filter chips.
//
// DeviceListScreen itself can't be pumped offline (it builds APIClient +
// DeviceGroupsService and loads over the network), so the chip row was
// extracted into DeviceGroupFilterChips to make this the one screen-level
// control that gets real tap-target and large-text coverage.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/features/devices/widgets/device_group_filter_chips.dart';
import 'package:jkbmsr_pro/services/device_groups_service.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

import 'a11y_support.dart';

Widget _wrap(Widget child, {double textScale = 1.0}) {
  return MaterialApp(
    theme: JKBMSRTheme.darkTheme,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: child),
      ),
    ),
  );
}

Widget _chips() {
  return DeviceGroupFilterChips(
    groups: [
      DeviceGroup(id: 'g1', name: 'Home'),
      DeviceGroup(id: 'g2', name: 'Warehouse backup bank'),
      DeviceGroup(id: 'g3', name: 'Guest cabin'),
    ],
    selectedGroupId: 'g2',
    onSelected: (_) {},
    onCreateGroup: () {},
    onEditGroup: (_) {},
  );
}

void _phoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('group filter chips expose >=48dp tap targets', (tester) async {
    _phoneViewport(tester);
    await tester.pumpWidget(_wrap(_chips()));
    await expectTapTargetsAtLeast(tester, minSize: 48, where: 'device group filter chips');
  });

  testWidgets('group filter chips expose >=48dp tap targets at textScale 2.0', (tester) async {
    _phoneViewport(tester);
    await tester.pumpWidget(_wrap(_chips(), textScale: 2.0));
    await expectTapTargetsAtLeast(tester, minSize: 48, where: 'device group filter chips at 2.0');
  });

  testWidgets('group filter chips do not overflow at textScale 2.0', (tester) async {
    _phoneViewport(tester);
    await tester.pumpWidget(_wrap(_chips(), textScale: 2.0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a group chip reports its id, and All clears the filter', (tester) async {
    _phoneViewport(tester);
    String? selected = 'g2';
    await tester.pumpWidget(_wrap(DeviceGroupFilterChips(
      groups: [DeviceGroup(id: 'g1', name: 'Home'), DeviceGroup(id: 'g2', name: 'Guest cabin')],
      selectedGroupId: selected,
      onSelected: (id) => selected = id,
      onCreateGroup: () {},
      onEditGroup: (_) {},
    )));

    await tester.tap(find.text('Home'));
    expect(selected, 'g1');

    await tester.tap(find.text('All'));
    expect(selected, isNull);
  });
}
