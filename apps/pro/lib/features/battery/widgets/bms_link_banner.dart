import 'package:flutter/material.dart';

import '../../../models/telemetry.dart';
import '../../../widgets/shared/design_system/components.dart';

/// The gateway Overview's "online but the BMS link is down" explanation.
///
/// A gateway whose BMS link is down keeps heartbeating, so it still shows as
/// online — but every reading is empty, which looks like the app is broken. The
/// truth is in the telemetry `diagnostics` object the API already returns
/// (`bmsLinkUp` plus the BLE state/error/RSSI); this banner surfaces it.
///
/// It renders [SizedBox.shrink] whenever the link is up *or unknown*, so a
/// healthy gateway gets no permanent chrome, and an older payload that simply
/// omits `bmsLinkUp` is never reported as broken.
class BmsLinkBanner extends StatelessWidget {
  final Telemetry? telemetry;

  const BmsLinkBanner({Key? key, required this.telemetry}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final link = telemetry?.linkDiagnostics;
    if (link == null || !link.isDown) {
      return const SizedBox.shrink();
    }

    final details = <String>[
      if (link.lastError.trim().isNotEmpty) 'Last BLE error: ${link.lastError.trim()}',
      if (link.rssi > -128) 'BMS signal: ${link.rssi} dBm',
      'Check the BMS is powered and awake, that the BLE or wired link is '
          'connected, and that the gateway is within signal range.',
    ];

    return JKBMSRAlertBanner(
      tone: JKBMSRAlertTone.warning,
      icon: Icons.link_off,
      title: 'Gateway online — no data from the BMS',
      message: 'The gateway is connected, but it has no link to the battery, so '
          'the readings on this screen stay empty. It recovers automatically '
          'once the link is back.',
      details: details,
    );
  }
}
