import 'package:flutter/material.dart';
import '../models/bms_models.dart';
import '../models/bms_parameter.dart';
import '../services/ble_service.dart';
import '../widgets/motion_kit.dart';
import '../widgets/battery_hero_card.dart';
import '../widgets/brand_hero_strip.dart';
import '../widgets/quick_toggle_cards.dart';
import '../widgets/alerts_section.dart';
import '../widgets/bms_info_section.dart';
import '../widgets/bms_device_info_section.dart';
import '../widgets/bms_logbook_section.dart';
import '../widgets/battery_metrics_grid.dart';
import '../widgets/temperatures_section.dart';
import '../widgets/cell_voltages_section.dart';
import '../widgets/wire_resistance_section.dart';
import '../widgets/diagnostics_expandable.dart';
import '../widgets/info_banner.dart';
import '../widgets/ad_slot.dart';

class StatusScreen extends StatelessWidget {
  const StatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bleService = BleBmsService();

    return StreamBuilder<BmsStatus>(
      stream: bleService.statusStream,
      initialData: bleService.currentStatus,
      builder: (context, snapshot) {
        final status = snapshot.data ?? bleService.currentStatus;
        final isConnected = bleService.isConnected;
        // isConnected alone only means the BLE link is up — BmsStatus's
        // fields default to non-zero demo placeholder values (280Ah
        // capacity, 42 cycles, 38.5°C, etc.), so until a real frame has
        // actually been parsed, showing them gated only on isConnected
        // renders those placeholders as if they were live hardware
        // readings. hasLiveData tracks whether that's actually happened.
        final hasLiveData = isConnected && bleService.hasLiveData;
        final brand = bleService.connectedBrand;
        // Per-cell voltage telemetry isn't decoded for every brand: Basen
        // and Tianpower split cell voltages across multiple chunked frames
        // this app doesn't request yet, and Offgridtec's protocol isn't
        // implemented at all (see BmsCapabilities / ble_service.dart).
        final cellDataSupported = !{
          BmsBrand.tianpower,
          BmsBrand.basen,
          BmsBrand.ogt,
          BmsBrand.unknown,
        }.contains(brand);

        return StreamBuilder<String>(
          stream: bleService.logStream,
          builder: (context, logSnap) {
            final logs = bleService.rawLogs;

            // Reserve more bottom space as the floating nav bar grows with
            // the OS text scale, so it never overlaps the last content.
            final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;

            return JkAmbientBackground(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 100 + 62 * (textScale - 1)),
                physics: const BouncingScrollPhysics(),
                child: StaggerIn(
                  children: [
                  // BRAND IDENTITY — detected brand, accent-tinted, with a
                  // live-data-verified / still-detecting state chip.
                  BrandHeroStrip(
                    brand: brand,
                    modelName: status.modelName,
                    hasLiveData: hasLiveData,
                  ),
                  const SizedBox(height: 14),

                  // HERO CARD — status badge, animated SOC banner, headline
                  // voltage/current/power/temp metrics, and a cell-imbalance
                  // + balancing footer, modeled on jkbmsr-mobile's gateway
                  // dashboard card.
                  BatteryHeroCard(status: status, isConnected: hasLiveData),
                  const SizedBox(height: 14),

                  // LIVE STATUS (READ-ONLY — Control tab handles toggling)
                  QuickToggleCards(
                    switches: status,
                    isConnected: hasLiveData,
                  ),
                  const SizedBox(height: 14),

                  // ACTIVE BMS ALARMS (severity cards / all-clear)
                  AlertsSection(status: status, isConnected: hasLiveData),
                  const SizedBox(height: 14),

                  // BATTERY METRICS GRID (10-ITEM 2-COLUMN MATRIX)
                  BatteryMetricsGrid(status: status, isConnected: hasLiveData),
                  const SizedBox(height: 14),

                  // TEMPERATURES SECTION (MOS, BATTERY T1, BATTERY T2)
                  TemperaturesSection(status: status, isConnected: hasLiveData),
                  const SizedBox(height: 14),

                  // CELL VOLTAGES + WIRE RESISTANCE — depend on the
                  // connected BMS's model/brand actually reporting
                  // per-cell data over BLE.
                  if (isConnected && !cellDataSupported) ...[
                    InfoBanner(
                      icon: Icons.grid_view_rounded,
                      title: 'CELL DATA NOT AVAILABLE',
                      message:
                          "${brand.name.toUpperCase()} doesn't report per-cell voltage or wire-resistance data to this app yet — only JK-BMS is supported for that today.",
                    ),
                    const SizedBox(height: 14),
                  ] else ...[
                    CellVoltagesSection(cells: status.cells),
                    const SizedBox(height: 14),
                    WireResistanceSection(cells: status.cells),
                    const SizedBox(height: 14),
                  ],

                  // BATTERY / BMS INFORMATION
                  BmsInfoSection(status: status, isConnected: hasLiveData),
                  const SizedBox(height: 14),

                  // HARDWARE IDENTITY + ON-BOARD EVENT LOG. Both are JK-BMS
                  // only: the device-info (0x03) and logbook (0x05) frames
                  // exist only in the JK02 protocol, so no other brand shows
                  // a panel of dashes it can never fill.
                  if (brand == BmsBrand.jkbms) ...[
                    StreamBuilder<BmsModelInfo?>(
                      stream: bleService.deviceInfoStream,
                      initialData: bleService.currentDeviceInfo,
                      builder: (context, infoSnap) => BmsDeviceInfoSection(
                        info: infoSnap.data,
                        isConnected: hasLiveData,
                      ),
                    ),
                    const SizedBox(height: 14),
                    BmsLogbookSection(isConnected: hasLiveData),
                    const SizedBox(height: 14),
                  ],

                  // EXPANDABLE LIVE BLE DIAGNOSTICS STREAM
                  DiagnosticsExpandable(rawLogs: logs),
                  const SizedBox(height: 16),

                  // AD SLOT — read-only telemetry surface, the only kind of
                  // screen an ad may sit on. Renders nothing until an AdMob
                  // app id exists (see lib/services/ads_config.dart).
                  const AdSlot(),
                ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
