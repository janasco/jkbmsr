import 'dart:async';

import 'package:flutter/material.dart';
import '../models/bms_models.dart';
import '../services/ble_service.dart';
import '../services/brand_registry.dart';
import '../services/detection_engine.dart';
import '../widgets/motion_kit.dart';

class DevicesScreen extends StatefulWidget {
  final VoidCallback onConnected;
  const DevicesScreen({super.key, required this.onConnected});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _bleService = BleBmsService();

  @override
  void initState() {
    super.initState();
    _triggerScan();
  }

  /// Starts a scan — or restarts one that is already running. Deliberately not
  /// guarded on the current scan state: tapping while a scan is live is a
  /// manual reload, and it is safe because FlutterBluePlus stops the in-flight
  /// scan before opening the new window and the service resets its
  /// discovered-device map on every call.
  void _triggerScan() {
    unawaited(_bleService.startBleScan());
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild the scanner whenever the plugin's real scan state changes, so the
    // animation and the (re)start control always reflect a scan that is
    // actually running (startBleScan returns as soon as the scan has started).
    return StreamBuilder<bool>(
      stream: _bleService.scanStateStream,
      initialData: _bleService.isScanning,
      builder: (context, snapshot) =>
          _buildScannedBody(context, snapshot.data ?? false),
    );
  }

  Widget _buildScannedBody(BuildContext context, bool isScanning) {
    final connectedDev = _bleService.connectedDevice;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF131A20) : const Color(0xFFFFFFFF);
    final iconBg = isDark ? const Color(0xFF1E2830) : const Color(0xFFF1F5F9);
    final borderColor = isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

    // Reserve more bottom space as the floating nav bar grows with the OS
    // text scale, so it never overlaps the last content.
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;

    return JkAmbientBackground(
      child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 100 + 62 * (textScale - 1)),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SCAN HEADER CARD
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      // Static identity glyph. The scanning animation lives
                      // ONLY in the big centred ScanRadar in the empty-state
                      // card below; this small header icon used to run its own
                      // radar sweep while a scan was live, so two scanners
                      // animated at once. It is deliberately not animated now
                      // (and no longer changes size between idle/scanning), so
                      // exactly one scanner animates during a scan.
                      child: const Icon(Icons.radar_rounded, color: Color(0xFF0284C7), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DEVICE SCANNER',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          isScanning
                              ? const AnimatedDots(
                                  base: 'Scanning for nearby JK-BMS',
                                  style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                )
                              : const Text('Ready to discover balancers', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Always tappable: while a scan runs this means "start the scan
                // window again" (a manual reload), not a disabled spinner.
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF38BDF8),
                      foregroundColor: const Color(0xFF090D10),
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _triggerScan,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isScanning ? Icons.refresh_rounded : Icons.bluetooth_searching_rounded,
                          size: 18,
                          color: const Color(0xFF090D10),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isScanning ? 'SCAN AGAIN' : 'SCAN FOR DEVICES',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // DEVICES LIST
          const Text(
            'NEARBY BLUETOOTH DEVICES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 10),

          StreamBuilder<List<BleDeviceInfo>>(
            stream: _bleService.devicesStream,
            initialData: const [],
            builder: (context, snapshot) {
              final devices = snapshot.data ?? [];

              if (devices.isEmpty) {
                // While the scan is live but has found nothing yet, show a few
                // placeholder device cards beneath the radar. They mirror a
                // real result card's height so the first device to appear does
                // not shift the layout.
                final emptyState = Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        // The one and only animated scanner: the big centred
                        // radar is the single element allowed to sweep while a
                        // scan runs (the small header icon is static).
                        isScanning
                            ? const ScanRadar(size: 64, color: Color(0xFF10B981))
                            : const Icon(
                                Icons.bluetooth_disabled_rounded,
                                color: Color(0xFF64748B),
                                size: 40,
                              ),
                        const SizedBox(height: 12),
                        isScanning
                            ? AnimatedDots(
                                base: 'Scanning 2.4GHz Spectrum',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF10B981)),
                              )
                            : Text('No Bluetooth Devices Found', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textPrimary)),
                        const SizedBox(height: 4),
                        const Text(
                          'Ensure your BMS Bluetooth module is powered and nearby. A blue "JK-BMS" style tag appears next to devices this app recognizes.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                );

                if (!isScanning) return emptyState;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    emptyState,
                    const SizedBox(height: 10),
                    for (int i = 0; i < 3; i++) ...[
                      _SkeletonDeviceCard(
                        cardBg: cardBg,
                        borderColor: borderColor,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: devices.length,
                itemBuilder: (context, idx) {
                  final dev = devices[idx];
                  final isConn = connectedDev != null && connectedDev.remoteId.str == dev.id;
                  final candidates =
                      DetectionEngine.candidatesFor(name: dev.name, serviceUuids: dev.serviceUuids);
                  final top = candidates.isEmpty ? null : candidates.first;

                  // Entrance animation keyed by device id: newly discovered
                  // devices slide in as the scan finds them, while already-
                  // visible cards don't re-run the animation on rebuilds.
                  return _EntranceCard(
                    key: ValueKey(dev.id),
                    child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isConn
                            ? (isDark ? const Color(0xFF0A1A14) : const Color(0xFFD1FAE5))
                            : cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isConn ? const Color(0xFF10B981) : borderColor,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: isConn
                                      ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                      : iconBg,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.bluetooth_rounded,
                                  color: isConn ? const Color(0xFF10B981) : const Color(0xFF64748B),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          dev.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary),
                                        ),
                                      ),
                                      if (isConn) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF10B981),
                                            borderRadius: BorderRadius.circular(10),
                                          ),                                            child: Row(
                                              children: [
                                                const Icon(Icons.check_circle_rounded, size: 10, color: Color(0xFF090D10)),
                                                const SizedBox(width: 2),
                                                const PulseDot(color: Color(0xFF090D10), size: 5),
                                              Text(
                                                'CONNECTED',
                                                style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Color(0xFF090D10)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${dev.id}  •  ${dev.rssi} dBm',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontFamily: 'monospace'),
                                  ),
                                  if (top != null && top.brand != BmsBrand.unknown) ...[
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 5,
                                      runSpacing: 4,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: _designFor(top.brand).accent.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                _designFor(top.brand).icon,
                                                size: 10,
                                                color: _designFor(top.brand).accent,
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                _designFor(top.brand).tag.toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 11.0,
                                                  fontWeight: FontWeight.w900,
                                                  color: _designFor(top.brand).accent,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: (top.confidence >= 0.6 ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
                                                .withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '${(top.confidence * 100).round()}% ${top.brand == dev.brand && dev.brand != BmsBrand.unknown ? 'MATCH' : 'MATCH CANDIDATE'}',
                                            style: TextStyle(
                                              fontSize: 8,
                                              fontWeight: FontWeight.w900,
                                              color: top.confidence >= 0.6 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                            ),
                                          ),
                                        ),
                                        if (top.requiresProbe) ...[
                                          const SizedBox(width: 5),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'SNIFFED ON CONNECT',
                                              style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Color(0xFF38BDF8)),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      top.reason,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11.0, color: Color(0xFF64748B)),
                                    ),
                                  ] else if (dev.looksLikeBms) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'POSSIBLE BMS',
                                        style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.w900, color: Color(0xFFF59E0B)),
                                      ),
                                    ),
                                  ],
                                ],
                                ),
                              ),
                            ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: isConn ? 'Disconnect' : 'Connect',
                            style: IconButton.styleFrom(
                              backgroundColor: isConn
                                  ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                                  : (isDark ? const Color(0xFF1E2830) : const Color(0xFFF1F5F9)),
                              foregroundColor: isConn ? const Color(0xFFEF4444) : const Color(0xFF0284C7),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: isConn ? const Color(0xFFEF4444).withValues(alpha: 0.5) : borderColor,
                                ),
                              ),
                              padding: const EdgeInsets.all(10),
                              minimumSize: const Size(40, 40),
                            ),
                            onPressed: () async {
                              if (isConn) {
                                _bleService.disconnect();
                              } else {
                                final success = await _bleService.connectDevice(dev.id);
                                if (success && mounted) {
                                  widget.onConnected();
                                }
                              }
                            },
                            icon: Icon(
                              isConn ? Icons.link_off_rounded : Icons.link_rounded,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
                },
              );
            },
          ),
        ],
      ),
    ),
  );
}

  BrandDesign _designFor(BmsBrand brand) => BrandRegistry.designFor(brand);
}

/// Slide+fade entrance for scan-result cards. The ValueKey(deviceId) on the
/// parent means a card entering the list for the first time animates in;
/// rebuilds of already-visible cards keep their element (and animation
/// state) and don't re-run it.
class _EntranceCard extends StatelessWidget {
  final Widget child;

  const _EntranceCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}

/// Placeholder for a scan-result card while a scan runs and nothing has been
/// found yet. Same radius, padding, leading icon box, line heights and trailing
/// control box as a real result card, so the first device to appear slides into
/// place without reflowing the list.
class _SkeletonDeviceCard extends StatelessWidget {
  final Color cardBg;
  final Color borderColor;

  const _SkeletonDeviceCard({required this.cardBg, required this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: const Row(
        children: [
          JkSkeleton(width: 40, height: 40, borderRadius: 12),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                JkSkeleton(width: 150, height: 13, borderRadius: 4),
                SizedBox(height: 7),
                JkSkeleton(width: 96, height: 10, borderRadius: 4),
              ],
            ),
          ),
          SizedBox(width: 8),
          JkSkeleton(width: 40, height: 40, borderRadius: 12),
        ],
      ),
    );
  }
}
