import '../services/theme_service.dart';
import 'package:flutter/material.dart';

import 'in_app_browser.dart';
import 'motion_kit.dart';

class AboutModal extends StatelessWidget {
  final VoidCallback onClose;
  const AboutModal({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.bgCard(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.borderColor(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: StaggerIn(
          stepMs: 70,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                // The mark is a dark tile on dark surfaces and a white tile
                // with a dark-on-white mark on light surfaces, so it reads
                // against whichever theme the app is currently using.
                AppColors.isDark(context)
                    ? 'assets/icon/app_icon.png'
                    : 'assets/icon/app_icon_light.png',
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 64,
                  height: 64,
                  color: const Color(0xFF1E2830),
                  child: const Icon(Icons.bolt_rounded, color: Color(0xFF10B981), size: 36),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'About JKBMSR BLE',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context)),
            ),
            const SizedBox(height: 4),
            const Text(
              'Version 4.17.20 (Build 40)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF10B981), fontFamily: 'monospace', fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'JKBMSR BLE connects directly to your JK-BMS Bluetooth module for real-time '
              'telemetry, cell-level diagnostics, and power-flow visualization, with hardware '
              'control where the JK-BMS protocol supports it.',
              textAlign: TextAlign.left,
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), height: 1.45),
            ),
            const SizedBox(height: 8),
            const Text(
              'JK BMS Remote is an independent project and is not affiliated with, endorsed by, or '
              'sponsored by JK-BMS.',
              textAlign: TextAlign.left,
              style: TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.45),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E2830),
                  foregroundColor: const Color(0xFF38BDF8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                // Opens in our own sandboxed browser (header/footer chrome,
                // navigation locked to jkbmsr.com) instead of bouncing the
                // user to the system browser. See in_app_browser.dart.
                onPressed: () => Navigator.of(context).push(
                  InAppBrowserModal.route(
                    initialUrl: 'https://www.jkbmsr.com',
                    title: 'JKBMSR',
                  ),
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Visit www.jkbmsr.com', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF64748B),
                  side: BorderSide(color: AppColors.borderColor(context)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: onClose,
                child: const Text('CLOSE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
