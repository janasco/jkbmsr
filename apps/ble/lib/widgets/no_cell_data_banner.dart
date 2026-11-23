import 'package:flutter/material.dart';

import '../models/bms_models.dart';
import 'info_banner.dart';

/// A connected pack that reports no voltage for any cell.
///
/// Two donated captures arrived in exactly this state: 75 and 76 samples, with the
/// cell region of every frame zero while the model, settings and logbook parsed
/// normally. Before this, `CellVoltagesSection` returned `SizedBox.shrink()` for an
/// empty cell list, so the grid simply disappeared and the screen said nothing at
/// all. That is the same failure as a status card that reads "all good": the reader
/// cannot tell a pack with no data from a pack with nothing to report.
///
/// The wording separates the expected case (a bench pack, or sense wires off) from
/// the one worth acting on, because "no cell data" on its own sends people to
/// support with no next step.
class NoCellDataBanner extends StatelessWidget {
  final BmsStatus status;

  const NoCellDataBanner({super.key, required this.status});

  static String message(BmsStatus status) {
    final volts = status.totalVoltage;
    if (volts > 0.5) {
      return 'The pack reads ${volts.toStringAsFixed(1)} V, so it is powered, but the BMS '
          'reports 0 V for every cell. Check the balance wires and the cell count '
          'setting, then reconnect.';
    }
    return 'The BMS is connected but reports no cell voltages. If this pack is on a '
        'bench, or its balance wires are not connected yet, that is expected. '
        'Otherwise check the balance wires and the cell count setting.';
  }

  @override
  Widget build(BuildContext context) {
    return InfoBanner(
      icon: Icons.battery_alert_rounded,
      title: 'NO CELL VOLTAGES REPORTED',
      message: message(status),
    );
  }
}
