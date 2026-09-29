import 'package:flutter/material.dart';

import '../services/ads_config.dart';
import '../services/entitlement_service.dart';
import '../services/theme_service.dart';
import 'motion_kit.dart';
import 'supporter_section.dart';

/// The Support sheet — the one place a Google Play user buys the one-time
/// Supporter unlock (`remove_ads_lifetime`) that removes ads, and restores it
/// on a new device.
///
/// The app is **ads-only**: donations were removed, so this sheet does not
/// sell, link to, or mention a donation, and there is no external-payment or
/// checkout surface here. The only purchase it can start is the Play
/// non-consumable above, and a sideloaded copy (which never touches Play) has
/// no purchase surface here at all.
class SupportModal extends StatelessWidget {
  final VoidCallback onClose;
  const SupportModal({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(20),
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
        child: ValueListenableBuilder<EntitlementState>(
          valueListenable: EntitlementService.instance.changes,
          builder: (context, entitlement, _) => SingleChildScrollView(
            child: StaggerIn(
              stepMs: 70,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 24),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                      ),
                      child: const Icon(Icons.favorite_rounded,
                          color: Color(0xFFEF4444), size: 26),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded,
                          color: Color(0xFF64748B), size: 20),
                      onPressed: onClose,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Support JKBMSR',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary(context)),
                ),
                const SizedBox(height: 4),
                Text(
                  _statusCopy(entitlement),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 16),

                // SUPPORTER (Play builds only) — the one-time ad-removal
                // purchase, and the restore action for a Supporter who
                // reinstalls on a new device.
                if (entitlement.installKind.isPlayManaged) ...[
                  const SupporterSection(),
                  const SizedBox(height: 12),
                ],

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF64748B),
                      side: BorderSide(color: AppColors.borderColor(context)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: onClose,
                    child: const Text('CLOSE',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Truthful one-liner for the current state. It deliberately promises
  /// nothing the build does not do: with no AdMob id the app is simply
  /// ad-free today, and a Supporter sees their entitlement confirmed.
  String _statusCopy(EntitlementState entitlement) {
    if (entitlement.adFree && !entitlement.installKind.isPlayManaged) {
      // A sideloaded copy is ad-free by policy, not by purchase.
      return 'This copy is already ad-free.';
    }
    if (entitlement.adFree) {
      return 'You are a Supporter — this app is ad-free.';
    }
    if (!AdsConfig.current.isConfigured) {
      return 'JKBMSR BLE is free and ad-free.';
    }
    return 'JKBMSR BLE is free. The one-time Supporter unlock removes ads.';
  }
}
