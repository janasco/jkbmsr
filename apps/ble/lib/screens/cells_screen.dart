import 'package:flutter/material.dart';

import '../models/bms_models.dart';
import '../services/ble_service.dart';
import '../widgets/motion_kit.dart';
import '../widgets/cell_voltages_section.dart';
import '../widgets/temperatures_section.dart';
import '../widgets/info_banner.dart';
import '../widgets/ad_slot.dart';

/// Dedicated Cells tab — per-cell voltages, balance state, and temperatures.
/// Promoted to a bottom-nav tab (it replaced the Control tab, which now lives
/// in the drawer) because cell-level monitoring is the app's core use.
class CellsScreen extends StatelessWidget {
  const CellsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bleService = BleBmsService();

    return StreamBuilder<BmsStatus>(
      stream: bleService.statusStream,
      initialData: bleService.currentStatus,
      builder: (context, snapshot) {
        final status = snapshot.data ?? bleService.currentStatus;
        final isConnected = bleService.isConnected;
        final hasLiveData = isConnected && bleService.hasLiveData;
        final brand = bleService.connectedBrand;
        // Basen/Tianpower split cell voltages across chunked frames this app
        // doesn't request yet; OGT isn't implemented (see bms_models.dart).
        final cellDataSupported = !{
          BmsBrand.tianpower,
          BmsBrand.basen,
          BmsBrand.ogt,
          BmsBrand.unknown,
        }.contains(brand);

        // Reserve more bottom space as the floating nav bar grows with the
        // OS text scale, so it never overlaps the last content.
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;

        return JkAmbientBackground(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 100 + 62 * (textScale - 1)),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!hasLiveData)
                  const InfoBanner(
                    icon: Icons.grid_view_rounded,
                    title: 'NO CELL DATA',
                    message: 'Connect to a BMS to see per-cell voltages, balance state, and temperatures.',
                  )
                else if (!cellDataSupported)
                  InfoBanner(
                    icon: Icons.grid_view_rounded,
                    title: 'CELL DATA NOT AVAILABLE',
                    message:
                        "${brand.name.toUpperCase()} doesn't report per-cell voltage or wire-resistance data to this app yet — only JK-BMS is supported for that today.",
                  )
                else
                  CellVoltagesSection(cells: status.cells),
                const SizedBox(height: 16),
                TemperaturesSection(status: status, isConnected: hasLiveData),
                const SizedBox(height: 16),

                // AD SLOT — read-only cell/temperature history, so an ad can
                // never be mistaken for a control. Renders nothing until an
                // AdMob app id exists (see lib/services/ads_config.dart).
                const AdSlot(),
              ],
            ),
          ),
        );
      },
    );
  }
}
