import 'package:flutter/material.dart';

import '../services/entitlement_service.dart';

/// The Supporter unlock inside the Support sheet: buy the one-time
/// non-consumable that removes ads, and re-apply an existing purchase on a new
/// device.
///
/// Shown only in a Google Play install — a sideloaded copy is already ad-free
/// and has no Play account to bill, so there is nothing to sell it. The
/// install channel comes from [EntitlementService], the same single source of
/// truth the ad seam reads.
class SupporterSection extends StatefulWidget {
  const SupporterSection({super.key, this.entitlementService});

  /// Defaults to the app-wide instance. Tests pass their own so the section
  /// never has to reach for a real store.
  final EntitlementService? entitlementService;

  @override
  State<SupporterSection> createState() => _SupporterSectionState();
}

enum _Stage { loading, offered, owned, busy, failed }

class _SupporterSectionState extends State<SupporterSection> {
  _Stage _stage = _Stage.loading;
  String? _price;
  String? _message;
  bool _adFree = false;

  EntitlementService get _entitlements => widget.entitlementService ?? EntitlementService.instance;

  @override
  void initState() {
    super.initState();
    // Seed from the service: the entitlement is usually already resolved by
    // the time this sheet opens, and a supporter must not be shown a "buy"
    // button for an unlock they already own.
    _adFree = _entitlements.isAdFreeNow;
    _entitlements.changes.addListener(_onEntitlementChanged);
    _loadPrice();
  }

  @override
  void dispose() {
    _entitlements.changes.removeListener(_onEntitlementChanged);
    super.dispose();
  }

  void _onEntitlementChanged() {
    if (!mounted) return;
    setState(() => _adFree = _entitlements.isAdFreeNow);
  }

  Future<void> _loadPrice() async {
    final price = await _entitlements.supporterPrice();
    if (!mounted) return;
    setState(() {
      _price = price;
      _stage = _entitlements.isAdFreeNow
          ? _Stage.owned
          : (price == null ? _Stage.failed : _Stage.offered);
    });
  }

  Future<void> _buy() async {
    setState(() {
      _stage = _Stage.busy;
      _message = null;
    });
    final result = await _entitlements.buySupporter();
    if (!mounted) return;
    switch (result) {
      case BuyStatus.started:
        setState(() {
          _stage = _Stage.busy;
          _message = 'Finishing up with Google Play…';
        });
      case BuyStatus.unavailable:
        setState(() {
          _stage = _Stage.failed;
          _message = 'The Supporter unlock is not available in this build yet.';
        });
      case BuyStatus.failed:
        setState(() {
          _stage = _Stage.failed;
          _message = 'Google Play could not start this purchase.';
        });
    }
  }

  Future<void> _restore() async {
    setState(() {
      _stage = _Stage.busy;
      _message = null;
    });
    final result = await _entitlements.restorePurchases();
    if (!mounted) return;
    setState(() {
      _adFree = _entitlements.isAdFreeNow;
      _stage = _adFree ? _Stage.owned : _Stage.offered;
      _message = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    // No store behind this copy (or the channel isn't resolved yet): there is
    // no product to buy and no purchase to restore.
    if (!_entitlements.installKind.isPlayManaged) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF090D10) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded, color: Color(0xFF38BDF8), size: 18),
              const SizedBox(width: 8),
              Text(
                'SUPPORTER',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.9,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _blurb(),
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF94A3B8),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          if (_adFree)
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ads are off for good.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF38BDF8),
                  foregroundColor: const Color(0xFF090D10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _stage == _Stage.busy ? null : _buy,
                icon: _stage == _Stage.busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF090D10)),
                      )
                    : const Icon(Icons.block_rounded, size: 16),
                label: Text(
                  _price == null ? 'REMOVE ADS' : 'REMOVE ADS · ${_price!.toUpperCase()}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          if (!_adFree) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF38BDF8),
                  side: BorderSide(color: borderColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _stage == _Stage.busy ? null : _restore,
                icon: const Icon(Icons.restore_rounded, size: 16),
                label: const Text(
                  'RESTORE PURCHASE',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
          if (_message != null && _message!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _message!,
              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), height: 1.3),
            ),
          ],
        ],
      ),
    );
  }

  String _blurb() {
    if (_adFree) {
      return 'You own the Supporter unlock on this Google Play account, so '
          'this app stays ad-free on every device you use it on. No JKBMSR '
          'account needed.';
    }
    // A Supporter unlock grants a real in-app benefit (no ads), so it is a
    // digital purchase and must be paid for through Google Play Billing.
    return 'One payment, not a subscription. Removing ads is a one-time '
        'Supporter purchase and it follows your Google Play account to any '
        'device this app is installed on.';
  }
}
