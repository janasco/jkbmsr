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
import 'package:jkbmsr_ble/models/bms_models.dart';
import 'package:jkbmsr_ble/widgets/battery_metrics_grid.dart';
import 'package:jkbmsr_ble/widgets/bottom_nav_bar.dart';
import 'package:jkbmsr_ble/widgets/cell_voltages_section.dart';
import 'package:jkbmsr_ble/widgets/soc_ring.dart';
import 'package:jkbmsr_ble/widgets/wire_resistance_section.dart';

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
  });
}
