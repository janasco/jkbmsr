import 'package:flutter/material.dart';
import '../services/brand_registry.dart';
import '../widgets/motion_kit.dart';

/// First-run screen shown until the user has connected a BMS at least once
/// (BleBmsService.lastDeviceId is null). Introduces the app, the detected
/// brand (once one is seen), and funnels straight into the device scanner.
///
/// Uses the app's living-design language: the ambient drifting background,
/// staggered entrance choreography, a radar hero mark with a breathing bolt,
/// and a glowing call-to-action.
class WelcomeScreen extends StatelessWidget {
  final VoidCallback onStartScanning;

  const WelcomeScreen({super.key, required this.onStartScanning});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF090D10) : const Color(0xFFF8FAFC),
      body: JkAmbientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            physics: const BouncingScrollPhysics(),
            child: StaggerIn(
              stepMs: 70,
              children: [
                const SizedBox(height: 16),
                const _HeroMark(),
                const SizedBox(height: 20),
                Text(
                  'WELCOME TO JK BMS BLUETOOTH',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 1.4, color: textPrimary),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Live telemetry, cell diagnostics and hardware control for your Bluetooth BMS.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
                ),
                const SizedBox(height: 28),

                // Brand support preview.
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF131A20) : const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SUPPORTED HARDWARE',
                        style: TextStyle(
                          fontSize: 11.0,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final design in BrandRegistry.selectableBrands) ...[
                        Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: design.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Icon(design.icon, size: 16, color: design.accent),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                design.name,
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: textPrimary),
                              ),
                            ),
                            Text(
                              design.tag.toUpperCase(),
                              style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.w900, color: design.accent),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      Text(
                        'JK BMS Remote is an independent project and is not affiliated with, '
                        'endorsed by, or sponsored by JK-BMS.',
                        style: TextStyle(fontSize: 11.0, height: 1.4, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // How it works.
                const _InfoRow(
                  icon: Icons.radar_rounded,
                  color: Color(0xFF38BDF8),
                  title: 'Auto-detection',
                  subtitle: 'The app sniffed out the brand from the device name and GATT services — '
                      'then confirms it by probing with the real request command.',
                ),
                const SizedBox(height: 10),
                const _InfoRow(
                  icon: Icons.tune_rounded,
                  color: Color(0xFF8B5CF6),
                  title: 'Live parameter editing',
                  subtitle: 'Read the real settings frame and write values back with the verified '
                      'JK-BMS protocol.',
                ),
                const SizedBox(height: 10),
                const _InfoRow(
                  icon: Icons.shield_rounded,
                  color: Color(0xFF10B981),
                  title: 'PIN-gated controls',
                  subtitle: 'Every switch and parameter write unlocks with your local security PIN.',
                ),

                const SizedBox(height: 28),
                PulseGlow(
                  color: const Color(0xFF10B981),
                  borderRadius: 14,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: const Color(0xFF090D10),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: onStartScanning,
                    icon: const Icon(Icons.bluetooth_searching_rounded, size: 20),
                    label: const Text('START SCANNING', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Radar sweep with the breathing brand bolt at its center — the app is
/// literally ready to hunt for devices the moment you land here.
class _HeroMark extends StatelessWidget {
  const _HeroMark();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ScanRadar(size: 132, color: Color(0xFF10B981)),
          PulseGlow(
            color: Color(0xFF10B981),
            borderRadius: 22,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0x2610B981),
                borderRadius: BorderRadius.all(Radius.circular(22)),
              ),
              child: SizedBox(
                width: 64,
                height: 64,
                child: Center(
                  child: Icon(Icons.bolt_rounded, size: 36, color: Color(0xFF10B981)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _InfoRow({required this.icon, required this.color, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textPrimary)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), height: 1.35)),
            ],
          ),
        ),
      ],
    );
  }
}
