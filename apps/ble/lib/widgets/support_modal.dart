import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'donate_modal.dart';
import 'supporter_section.dart';
import '../services/ads_config.dart';
import '../services/entitlement_service.dart';
import '../services/theme_service.dart';
import 'motion_kit.dart';

class SupportModal extends StatelessWidget {
  final VoidCallback onClose;
  const SupportModal({super.key, required this.onClose});

  static const String _donationWallUrl = 'https://jkbmsr.com/donations';

  // The EMVCo QRPh payload decoded byte-exact from the original
  // assets/images/qr-code.jpg (CRC-16/CCITT-FALSE verified: 0x3AE8 over the
  // 129-char body matches the embedded 6304 tag). Rendering it natively keeps
  // every module crisp at any size — the JPEG was soft at 160px and the
  // compression artifacts hurt scanner reliability.
  static const String _qrPhPayload =
      String.fromEnvironment('QRPH_PAYLOAD', defaultValue: '');
  static const String _qrPhLabel =
      String.fromEnvironment('QRPH_LABEL', defaultValue: 'QRPh');

  /// True when this build was given payment details to show. A build without
  /// them renders no QR card at all, so a fork cannot inherit someone else's
  /// bank account by accident.
  static bool get hasQrPhDetails => _qrPhPayload.isNotEmpty;

  void _openDonate(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const DonateModal(),
    );
  }

  Future<void> _openDonationWall() async {
    try {
      await launchUrl(
        Uri.parse(_donationWallUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Nothing to recover — the wall is also linked from the donate sheet.
    }
  }

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
                        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                      ),
                      child: const Icon(Icons.favorite_rounded, color: Color(0xFFEF4444), size: 26),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 20),
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
                const Text(
                  'Help fund ongoing development and new feature updates.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 16),

                // SEND SUPPORT QR CARD — SIDELOAD ONLY.
                //
                // GCash / QRPh is an external payment method, and Google Play's
                // Payments policy forbids a Play-distributed app from leading a
                // user to any payment method other than Play Billing. A
                // Play-managed build therefore hides this card entirely — no
                // QR, no "send support" wording, no link. The channel decision
                // comes from EntitlementService, the same source of truth the
                // ad seam and the Supporter section use, so there is exactly one
                // place that knows whether this is a Play build.
                if (entitlement.installKind.allowsExternalPayments &&
                    hasQrPhDetails) ...[
                  _buildQrCard(context),
                  const SizedBox(height: 12),
                ],

                // SUPPORTER (Play builds only) — the one-time ad-removal
                // purchase and the restore action for a supporter who reinstalls
                // on a new device.
                if (entitlement.installKind.isPlayManaged) ...[
                  const SupporterSection(),
                  const SizedBox(height: 12),
                ],

                // Donation options: Google Play tips (store builds) + the public
                // donors wall. The old Polar card checkout was removed.
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.bgNested(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.borderColor(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.favorite_rounded, color: Color(0xFF10B981), size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Support JKBMSR',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF10B981)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entitlement.adFree
                            ? 'You are a Supporter — this app is ad-free. Donations fund test hardware, protocol work, and app development.'
                            : AdsConfig.current.isConfigured
                                ? 'JKBMSR BLE is free. Supporter purchases remove ads, and donations fund test hardware, protocol work, and app development.'
                                : 'JKBMSR BLE is free and ad-free. Donations fund test hardware, protocol work, and app development.',
                        textAlign: TextAlign.start,
                        style:
                            const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), height: 1.35),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: const Color(0xFF090D10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 3,
                            shadowColor: const Color(0xFF10B981).withValues(alpha: 0.3),
                          ),
                          onPressed: () => _openDonate(context),
                          icon: const Icon(Icons.shopping_bag_rounded, size: 16),
                          label: const Text(
                            'Donate via Google Play',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF10B981),
                            side: BorderSide(color: AppColors.borderColor(context)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: _openDonationWall,
                          icon: const Icon(Icons.open_in_new_rounded, size: 16),
                          label: const Text(
                            'View donation wall',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
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
                    child: const Text('CLOSE',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The QRPh "Send Support" card. Rendered ONLY in a sideloaded copy — see
  /// the gate above. An external payment method is never offered to a user of
  /// a Play-distributed build.
  Widget _buildQrCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgNested(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.qr_code_2_rounded, color: Color(0xFF38BDF8), size: 20),
              SizedBox(width: 8),
              Text(
                'Send Support',
                style:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF38BDF8)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Scan with any QRPh banking or e-wallet app',
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderColor(context)),
            ),
            child: QrImageView(
              data: _qrPhPayload,
              version: QrVersions.auto,
              size: 230,
              backgroundColor: Colors.white,
              gapless: true,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
            ),
          ),
          const SizedBox(height: 10),
          // Flexible: the monospace name line is the widest thing in the card
          // and overflowed the dialog on a 400dp phone.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 12),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  _qrPhLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.0,
                    color: Color(0xFF94A3B8),
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
