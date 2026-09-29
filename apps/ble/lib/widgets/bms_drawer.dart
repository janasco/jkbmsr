import 'package:flutter/material.dart';
import '../screens/bms_parameters_screen.dart';
import '../screens/control_screen.dart';
import 'motion_kit.dart';

class BmsDrawer extends StatelessWidget {
  final VoidCallback onNavigateToDevices;
  final VoidCallback onOpenSoftwareUpdate;
  final VoidCallback onOpenSupport;
  final VoidCallback onOpenAbout;

  const BmsDrawer({
    super.key,
    required this.onNavigateToDevices,
    required this.onOpenSoftwareUpdate,
    required this.onOpenSupport,
    required this.onOpenAbout,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final drawerBg = isDark ? const Color(0xFF131A20) : const Color(0xFFFFFFFF);
    final borderColor = isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

    return Drawer(
      backgroundColor: drawerBg,
      child: SafeArea(
        child: Column(
          children: [
            // DRAWER HEADER
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      // Dark tile in dark mode, white tile with a dark mark
                      // in light mode, so the logo always sits on a surface
                      // that matches the app theme.
                      isDark
                          ? 'assets/icon/app_icon.png'
                          : 'assets/icon/app_icon_light.png',
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 44,
                        height: 44,
                        color: const Color(0xFF1E2830),
                        child: const Icon(Icons.bolt_rounded, color: Color(0xFF10B981)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'JKBMSR BLE',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                            color: textPrimary,
                          ),
                        ),
                        const Text(
                          'JK-BMS ACTIVE BALANCER',
                          style: TextStyle(
                            fontSize: 11.0,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Divider(color: borderColor, height: 1),

            // DRAWER MENU ITEMS — stagger in as the drawer opens.
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                children: [
                  TileEntrance(
                    delayIndex: 0,
                    child: _buildMenuItem(
                    context: context,
                    icon: Icons.bluetooth_rounded,
                    iconColor: const Color(0xFF0284C7),
                    label: 'Devices',
                    onTap: () {
                      Navigator.pop(context);
                      onNavigateToDevices();
                    },
                  ),
                  ),
                  const SizedBox(height: 4),
                  TileEntrance(
                    delayIndex: 2,
                    child: _buildMenuItem(
                    context: context,
                    icon: Icons.power_settings_new_rounded,
                    iconColor: const Color(0xFF38BDF8),
                    label: 'Controls',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ControlScreen()),
                      );
                    },
                  ),
                  ),
                  const SizedBox(height: 4),
                  TileEntrance(
                    delayIndex: 1,
                    child: _buildMenuItem(
                    context: context,
                    icon: Icons.tune_rounded,
                    iconColor: const Color(0xFF8B5CF6),
                    label: 'BMS parameters',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const BmsParametersScreen()),
                      );
                    },
                  ),
                  ),
                  const SizedBox(height: 4),
                  TileEntrance(
                    delayIndex: 2,
                    child: _buildMenuItem(
                    context: context,
                    icon: Icons.arrow_circle_up_rounded,
                    iconColor: const Color(0xFF10B981),
                    label: 'Software update',
                    onTap: () {
                      Navigator.pop(context);
                      onOpenSoftwareUpdate();
                    },
                  ),
                  ),
                  const SizedBox(height: 4),
                  TileEntrance(
                    delayIndex: 3,
                    child: _buildMenuItem(
                    context: context,
                    icon: Icons.favorite_rounded,
                    iconColor: const Color(0xFFEF4444),
                    label: 'Support',
                    onTap: () {
                      Navigator.pop(context);
                      onOpenSupport();
                    },
                  ),
                  ),
                  const SizedBox(height: 4),
                  TileEntrance(
                    delayIndex: 4,
                    child: _buildMenuItem(
                    context: context,
                    icon: Icons.info_outline_rounded,
                    iconColor: const Color(0xFFF59E0B),
                    label: 'About JKBMSR BLE',
                    onTap: () {
                      Navigator.pop(context);
                      onOpenAbout();
                    },
                  ),
                  ),
                ],
              ),
            ),

            // DRAWER FOOTER
            Divider(color: borderColor, height: 1),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'JKBMSR 4.17.20 | BUILD 40',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        label,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary),
      ),
      onTap: onTap,
    );
  }
}
