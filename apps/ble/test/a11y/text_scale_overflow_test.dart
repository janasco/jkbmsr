// Accessibility device pass: large-text (dynamic type) overflow audit.
//
// Every section recently reworked for large-accessibility-text support is
// mounted at textScale 2.0 (the top of the 1.3–2.0 range the OS offers) on a
// narrow phone, with a 24-cell pack. A RenderFlex/layout overflow makes
// Flutter log an exception, which `tester.takeException()` surfaces — so the
// test fails loudly instead of shipping clipped content.
//
// The view is resized with `tester.view.physicalSize` (a MediaQuery above the
// app only changes the inherited value, not the layout constraints the
// render tree actually gets). The text scale is then overridden with a
// MediaQuery *inside* MaterialApp.
//
// Widgets that expect a scrollable context are wrapped in a
// SingleChildScrollView exactly like the existing tests. That hides *vertical*
// overflow of the outer column, but the overflow-prone parts here (the grids)
// use fixed `mainAxisExtent` heights, so any tile-internal overflow is still
// detected. BottomNavBar is given its real bounded constraints instead.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/main.dart';
import 'package:jkbmsr_ble/models/bms_models.dart';
import 'package:jkbmsr_ble/screens/status_screen.dart';
import 'package:jkbmsr_ble/services/ble_service.dart';
import 'package:jkbmsr_ble/widgets/battery_metrics_grid.dart';
import 'package:jkbmsr_ble/widgets/bottom_nav_bar.dart';
import 'package:jkbmsr_ble/widgets/cell_voltages_section.dart';
import 'package:jkbmsr_ble/widgets/soc_ring.dart';
import 'package:jkbmsr_ble/widgets/wire_resistance_section.dart';

import '../support/fake_universal_ble.dart';
import '../support/test_fonts.dart';

const double _largeTextScale = 2.0;

/// Applies the large text scale and, when [scrollable] (the default), wraps
/// the widget in a SingleChildScrollView like the existing per-widget tests.
Widget _wrapScaled(Widget child, {bool scrollable = true}) {
  return MaterialApp(
    theme: ThemeData.dark(),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(_largeTextScale),
        ),
        child: Scaffold(
          body: scrollable
              ? SingleChildScrollView(child: child)
              : child,
        ),
      ),
    ),
  );
}

void _phoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

List<CellInfo> _cells() => [
      for (var i = 1; i <= 24; i++)
        CellInfo(
          index: i,
          voltage: 3.2 + i * 0.01,
          wireResistance: i.isEven ? 0.0123 : 0.0012,
          isBalancing: i % 5 == 0,
        ),
    ];

BmsStatus _status() => BmsStatus(
      soc: 87,
      totalVoltage: 53.4,
      currentA: -12.34,
      powerW: -659.1,
      remainingCapacityAh: 243.6,
      nominalCapacityAh: 280,
      cycleCount: 1234,
      totalCycleCapacityAh: 11760.5,
      cells: _cells(),
      timestamp: DateTime(2026, 9, 22, 12, 0, 0),
    );

void main() {
  group('textScale 2.0 overflow', () {
    // The numeric values use `fontFamily: 'monospace'`, which the test engine
    // cannot resolve. Without a real face the measurements are of the test
    // font's ~2x advance, not of the app.
    setUpAll(loadMonospaceTestFont);
    setUp(installFakeUniversalBle);
    tearDown(() {
      BleBmsService().debugResetScanningState();
      BleBmsService().debugResetConnectionState();
    });

    testWidgets('Cell Voltages section does not overflow', (tester) async {
      _phoneViewport(tester);
      await tester.pumpWidget(_wrapScaled(CellVoltagesSection(cells: _cells())));
      // The MIN/MAX badges use PulseGlow, a perpetual breathing glow, so
      // pumpAndSettle would time out (reduced motion is off in this test, so
      // the glow animates). Two frames are enough for layout + the finite
      // entrance tweens.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Wire Resistance section does not overflow', (tester) async {
      _phoneViewport(tester);
      await tester.pumpWidget(_wrapScaled(WireResistanceSection(cells: _cells())));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Battery Metrics grid does not overflow', (tester) async {
      _phoneViewport(tester);
      await tester.pumpWidget(_wrapScaled(BatteryMetricsGrid(status: _status(), isConnected: true)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('SOC ring does not overflow', (tester) async {
      _phoneViewport(tester);
      await tester.pumpWidget(_wrapScaled(const SocRing(
        percent: 87,
        live: true,
        color: Color(0xFF10B981),
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Bottom nav bar does not overflow', (tester) async {
      _phoneViewport(tester);
      // Rendered with the real bounded constraints of a phone body, not an
      // unbounded scroll view — the bar has a fixed height that must fit.
      await tester.pumpWidget(_wrapScaled(
        BottomNavBar(currentTab: NavTab.status, onTabSelect: (_) {}),
        scrollable: false,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('app header does not overflow on a 360dp phone', (tester) async {
      // The real header: its title block must truncate rather than collide
      // with the fixed ON/OFF pill when the OS text scale doubles.
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // The scale is raised only after the CONTROLS tab is on screen. The
      // default STATUS tab has its own large-text overflow in sections that
      // are not part of this audit; rendering it at 2x first would put those
      // exceptions in the queue and this test could not say anything about the
      // header. Selecting a tab is a state change inside the app, so the
      // element (and `_currentTab`) survives the rebuild below.
      final scale = ValueNotifier<double>(1.0);
      addTearDown(scale.dispose);

      await tester.pumpWidget(ValueListenableBuilder<double>(
        valueListenable: scale,
        builder: (context, value, _) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(value),
          ),
          child: const JkbmsrBleApp(),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));

      // The first-run overlay covers the tab bar. Its call to action sits below
      // the fold on a phone this size, so scroll it into view before tapping.
      final start = find.text('START SCANNING');
      if (start.evaluate().isNotEmpty) {
        await tester.ensureVisible(start);
        await tester.pump();
        await tester.tap(start);
        await tester.pump(const Duration(milliseconds: 400));
      }

      // The longest tab title, which is the one that collided with the pill.
      await tester.tap(find.text('CONTROLS').last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('CONTROLS'), findsWidgets);

      scale.value = _largeTextScale;
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
    });

    testWidgets('STATUS tab does not overflow at 2x on a 360dp phone',
        (tester) async {
      // The whole status list, not one section: the Alerts header and the
      // Battery & BMS info label/value rows each overflowed on their own at
      // double text on a narrow phone. The header test above deliberately
      // avoids this tab for that reason; this is the case that pins it.
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Live values make the info rows show real strings ("243.6 Ah"), which
      // is where the label/value row has the least room.

      final scale = ValueNotifier<double>(1.0);
      addTearDown(scale.dispose);

      await tester.pumpWidget(ValueListenableBuilder<double>(
        valueListenable: scale,
        builder: (context, value, _) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(value),
          ),
          child: const JkbmsrBleApp(),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));

      // The first-run overlay covers the tab bar. Its call to action sits below
      // the fold on a phone this size, so scroll it into view before tapping.
      final start = find.text('START SCANNING');
      if (start.evaluate().isNotEmpty) {
        await tester.ensureVisible(start);
        await tester.pump();
        await tester.tap(start);
        await tester.pump(const Duration(milliseconds: 400));
      }

      await tester.tap(find.text('STATUS').last);
      await tester.pump(const Duration(milliseconds: 400));

      scale.value = _largeTextScale;
      await tester.pump(const Duration(milliseconds: 400));

      // Walk the status list to its end in steps, so every section is laid out
      // at the doubled scale rather than only what fits on the first screen.
      final scrollable = find
          .descendant(
            of: find.byType(StatusScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      for (var i = 0; i < 60; i++) {
        if (position.pixels >= position.maxScrollExtent) break;
        final target = position.pixels + 300;
        position.jumpTo(
          target > position.maxScrollExtent ? position.maxScrollExtent : target,
        );
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(position.pixels, position.maxScrollExtent,
          reason: 'the status list should be scrolled through to its end');

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'connected 24-cell pack at 2x does not overflow on a 360dp phone',
        (tester) async {
      // The idle STATUS case above renders no cells and no decoded identity,
      // so it never lays out the fixed four-column cell matrix or a real
      // label/value row. This seeds a CONNECTED 24-cell pack — the shape that
      // was measured — through the service's own publish seam, then walks the
      // whole status list at double text.
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final cells = [
        for (var i = 1; i <= 24; i++)
          CellInfo(
            index: i,
            voltage: 3.2 + i * 0.003,
            wireResistance: 0.1 + i * 0.01,
            isBalancing: i % 5 == 0,
          ),
      ];
      BleBmsService().debugPublishStatus(BmsStatus(
        soc: 87,
        totalVoltage: 53.4,
        currentA: -12.34,
        powerW: -659.1,
        remainingCapacityAh: 243.6,
        nominalCapacityAh: 280,
        cycleCount: 1234,
        totalCycleCapacityAh: 11760.5,
        cells: cells,
        enabledCellCount: 24,
        timestamp: DateTime(2026, 9, 22, 12),
      ));

      final scale = ValueNotifier<double>(1.0);
      addTearDown(scale.dispose);

      await tester.pumpWidget(ValueListenableBuilder<double>(
        valueListenable: scale,
        builder: (context, value, _) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(value),
          ),
          child: const JkbmsrBleApp(),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));

      // The first-run overlay still appears: the test has no stored device id.
      final start = find.text('START SCANNING');
      if (start.evaluate().isNotEmpty) {
        await tester.ensureVisible(start);
        await tester.pump();
        await tester.tap(start);
        await tester.pump(const Duration(milliseconds: 400));
      }

      await tester.tap(find.text('STATUS').last);
      await tester.pump(const Duration(milliseconds: 400));

      // The seeded pack must actually be on screen, or this test proves
      // nothing about the 24-cell matrix.
      expect(find.text('Cell voltages'), findsOneWidget);
      expect(find.text('C24'), findsWidgets);

      scale.value = _largeTextScale;
      await tester.pump(const Duration(milliseconds: 400));

      final scrollable = find
          .descendant(
            of: find.byType(StatusScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      for (var i = 0; i < 120; i++) {
        if (position.pixels >= position.maxScrollExtent) break;
        final target = position.pixels + 400;
        position.jumpTo(
          target > position.maxScrollExtent ? position.maxScrollExtent : target,
        );
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(position.pixels, position.maxScrollExtent,
          reason: 'the status list should be scrolled through to its end');

      // Every section has now been laid out at double text, including the
      // cell matrix and the device-info rows.
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Battery Metrics grid does not overflow at 2x on a 360dp phone',
        (tester) async {
      // The existing 400 dp case above fits two columns comfortably. On the
      // measured 360 dp phone the content is 328 dp, which is where the
      // longest value ("11760.5 Ah") had the least room.
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrapScaled(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: BatteryMetricsGrid(
            status: BmsStatus(
              soc: 87,
              totalVoltage: 53.4,
              currentA: -12.34,
              powerW: -659.1,
              remainingCapacityAh: 243.6,
              nominalCapacityAh: 280,
              cycleCount: 1234,
              totalCycleCapacityAh: 11760.5,
              timestamp: DateTime(2026, 9, 22, 12),
            ),
            isConnected: true,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
