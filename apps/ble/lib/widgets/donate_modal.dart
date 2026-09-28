import '../services/ads_config.dart';
import '../services/theme_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import 'motion_kit.dart';

/// Donation entry point for the standalone BLE app.
///
/// In-app donations go through native Google Play Billing (required for
/// store-distributed builds). The credit-card checkout — the embedded Polar
/// flow — was removed in favour of the public donors wall: sideloaded builds
/// with no Play products simply link out to jkbmsr.com/donations, and Play
/// donors can opt in to a wall credit afterwards.
///
/// The wall lives at https://jkbmsr.com/donations and reads the same public
/// API the preview here uses.
class DonateModal extends StatefulWidget {
  const DonateModal({super.key});

  @override
  State<DonateModal> createState() => _DonateModalState();
}

enum _Stage { choose, done }

enum _Backend { detecting, play, linkout }

class _DonateModalState extends State<DonateModal> {
  static const _playCreditEndpoint =
      'https://api.jkbmsr.com/ble/donate/play-credit';
  static const _wallEndpoint = 'https://api.jkbmsr.com/ble/donate/credits';
  static const _wallPageUrl = 'https://jkbmsr.com/donations';

  static const Set<String> _donationProductIds = {
    'donation_tier_3',
    'donation_tier_5',
    'donation_tier_10',
    'donation_tier_25',
    'donation_tier_50',
  };

  _Stage _stage = _Stage.choose;
  _Backend _backend = _Backend.detecting;

  // Play Billing state.
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  List<ProductDetails> _playTiers = const [];
  bool _playPending = false;
  String? _playToken; // verified purchase token for the wall credit
  String? _playProductId;

  bool _busy = false;
  String? _error;

  // Donor wall (opt-in, success only).
  bool _creditSaved = false;
  bool _creditSkipped = false;
  bool _creditBusy = false;
  String? _creditError;
  final _nameController = TextEditingController();
  final _messageController = TextEditingController();
  bool _hideAmount = false;
  List<Map<String, dynamic>>? _wall;

  @override
  void initState() {
    super.initState();
    _detectBackend();
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    _nameController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context, rootNavigator: true).pop();

  // ── Backend detection ───────────────────────────────────────────────────

  Future<void> _detectBackend() async {
    bool play = false;
    try {
      final iap = InAppPurchase.instance;
      if (await iap.isAvailable()) {
        const tiers = [
          'donation_tier_3',
          'donation_tier_5',
          'donation_tier_10',
          'donation_tier_25',
          'donation_tier_50',
        ];
        final response = await iap.queryProductDetails(tiers.toSet());
        play = response.productDetails.isNotEmpty;
        if (play) {
          _playTiers = response.productDetails.toList()
            ..sort((a, b) => a.price.compareTo(b.price));
          _purchaseSub = iap.purchaseStream.listen(
            _onPurchaseUpdates,
            onError: (_) {},
          );
        }
      }
    } catch (_) {
      play = false;
    }
    if (!mounted) return;
    setState(() => _backend = play ? _Backend.play : _Backend.linkout);
  }

  // ── Play Billing purchase handling ──────────────────────────────────────

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      // The purchase stream is app-wide, so it also carries the Supporter
      // (ad-removal) non-consumable. This sheet must leave that one alone:
      // acknowledging it here would race EntitlementService's own handler
      // and, worse, show a "thank you for your donation" state for a
      // purchase that wasn't one.
      if (!_donationProductIds.contains(purchase.productID)) continue;
      switch (purchase.status) {
        case PurchaseStatus.purchased:
          _playToken = purchase.verificationData.serverVerificationData;
          _playProductId = purchase.productID;
          try {
            await InAppPurchase.instance.completePurchase(purchase);
          } catch (_) {}
          if (!mounted) return;
          setState(() {
            _stage = _Stage.done;
            _playPending = false;
            _creditSaved = false;
            _creditSkipped = false;
            _creditError = null;
          });
          _loadWall();
          break;
        case PurchaseStatus.pending:
          if (!mounted) return;
          setState(() => _playPending = true);
          break;
        case PurchaseStatus.error:
          if (!mounted) return;
          setState(() {
            _playPending = false;
            _error = purchase.error?.message ?? 'Purchase was not completed.';
          });
          break;
        case PurchaseStatus.canceled:
          if (!mounted) return;
          setState(() => _playPending = false);
          break;
        case PurchaseStatus.restored:
          // Donations are consumables — nothing to restore. (The Supporter
          // non-consumable, which does restore, is handled by
          // EntitlementService, not here.)
          break;
      }
    }
  }

  Future<void> _buyTier(ProductDetails product) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await InAppPurchase.instance
          .buyConsumable(purchaseParam: PurchaseParam(productDetails: product));
      if (!ok && mounted) {
        setState(() => _error = 'Google Play could not start this purchase.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Google Play could not start this purchase.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens the public donors wall in the system browser.
  Future<void> _openWall() async {
    try {
      final opened = await launchUrl(
        Uri.parse(_wallPageUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        setState(() =>
            _error = 'Could not open the donors wall. Visit $_wallPageUrl');
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Could not open the donors wall. Visit $_wallPageUrl');
      }
    }
  }

  // ── Donor wall (opt-in) ─────────────────────────────────────────────────

  Future<void> _loadWall() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(Uri.parse('$_wallEndpoint?limit=12'));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      if (response.statusCode != 200) return;
      final data = jsonDecode(body) as Map<String, dynamic>;
      final credits = (data['credits'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted || credits == null) return;
      setState(() => _wall = credits);
    } catch (_) {
      // Wall preview is decorative — silently skip on any error.
    }
  }

  Future<void> _submitCredit() async {
    if (_creditBusy) return;
    final token = _playToken;
    if (token == null) return;
    setState(() {
      _creditBusy = true;
      _creditError = null;
    });
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      final request = await client.postUrl(Uri.parse(_playCreditEndpoint));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(<String, dynamic>{
        'name': _nameController.text.trim(),
        'message': _messageController.text.trim(),
        'hideAmount': _hideAmount,
        'productId': _playProductId,
        'purchaseToken': token,
      }));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      if (response.statusCode != 200) {
        String msg = 'Could not save your credit.';
        try {
          msg = (jsonDecode(body) as Map<String, dynamic>)['error'] as String? ??
              msg;
        } catch (_) {}
        throw HttpException(msg);
      }
      if (!mounted) return;
      setState(() => _creditSaved = true);
      _loadWall();
    } catch (e) {
      if (mounted) {
        setState(() => _creditError = e is HttpException && e.message.length < 80
            ? e.message
            : 'Could not save your credit. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _creditBusy = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

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
        child: _stage == _Stage.done ? _buildDone() : _buildChoose(),
      ),
    );
  }

  // ── Donation chooser ────────────────────────────────────────────────────

  Widget _buildChoose() {
    return StaggerIn(
      stepMs: 60,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(width: 40),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
              ),
              child:
                  const Icon(Icons.favorite_rounded, color: Color(0xFFEF4444), size: 26),
            ),
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 20),
              onPressed: _close,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Support JKBMSR',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context)),
        ),
        const SizedBox(height: 4),
        Text(
          _backend == _Backend.play
              ? 'Processed securely by Google Play. Add an optional wall credit afterwards.'
              : AdsConfig.current.isConfigured
                  ? 'JKBMSR BLE is free. Supporter purchases remove ads, and supporters can appear on the public donors wall.'
                  : 'JKBMSR BLE is free and ad-free. Supporters can appear on the public donors wall.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 16),
        if (_backend == _Backend.detecting)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: CircularProgressIndicator(color: Color(0xFF10B981), strokeWidth: 3),
          )
        else if (_backend == _Backend.play)
          _buildPlayTiers(),
        const SizedBox(height: 16),
        _buildWallButton(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: Color(0xFFF59E0B), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(fontSize: 11, color: Color(0xFFF59E0B)),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shield_rounded, color: Color(0xFF475569), size: 12),
            const SizedBox(width: 4),
            Text(
              _backend == _Backend.play
                  ? 'Billing by Google Play · Play Protect verified'
                  : 'Donations fund test hardware and protocol work',
              style: const TextStyle(fontSize: 11.0, color: Color(0xFF475569)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlayTiers() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final tier in _playTiers)
          GestureDetector(
            onTap: _busy ? null : () => _buyTier(tier),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.bgNested(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderColor(context)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tier.price,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF94A3B8)),
                      ),
                      if (_playPending)
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text(
                            'awaiting Google…',
                            style: TextStyle(fontSize: 11.0, color: Color(0xFFF59E0B)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWallButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF10B981),
          side: BorderSide(color: AppColors.borderColor(context)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 13),
        ),
        onPressed: _openWall,
        icon: const Icon(Icons.open_in_new_rounded, size: 15),
        label: const Text(
          'View donation wall',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  // ── Thank-you state (with optional donor credit) ────────────────────────

  Widget _buildDone() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
            ),
            child:
                const Icon(Icons.favorite_rounded, color: Color(0xFF10B981), size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            'Thank you! 💚',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your donation keeps JKBMSR BLE improving — better JK-BMS diagnostics, faster fixes.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), height: 1.45),
          ),
          const SizedBox(height: 20),
          _buildCreditSection(),
          if (_creditSaved || _creditSkipped) ...[
            const SizedBox(height: 14),
            _buildWallPreview() ?? const SizedBox.shrink(),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: const Color(0xFF090D10),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _close,
              child: const Text('DONE',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }

  /// Optional, privacy-respecting donor credit: every field is optional, the
  /// amount can be hidden, and skipping is one tap. Only shown after a
  /// verified successful Play purchase (the purchase token is verified
  /// server-side at submit time).
  Widget _buildCreditSection() {
    if (_creditSaved) {
      return _wallCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 16),
                SizedBox(width: 6),
                Text(
                  'You\'re on the wall!',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF10B981)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Your support is now visible on jkbmsr.com/donations and below.',
              style: TextStyle(
                  fontSize: 11,
                  color: const Color(0xFF94A3B8).withValues(alpha: 0.9)),
            ),
          ],
        ),
      );
    }
    if (_creditSkipped) return const SizedBox.shrink();

    return _wallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events_rounded, color: Color(0xFFF59E0B), size: 16),
              SizedBox(width: 6),
              Text(
                'Get credited (optional)',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary(context)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Appear on the donors wall. Everything is optional — leave it empty to stay anonymous.',
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            maxLength: 40,
            style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 14),
            decoration:
                _creditInputDecoration('Display name', Icons.person_rounded),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _messageController,
            maxLength: 140,
            maxLines: 2,
            style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 14),
            decoration: _creditInputDecoration(
                'Message (optional)', Icons.chat_bubble_rounded),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _hideAmount = !_hideAmount),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: _hideAmount,
                      onChanged: (v) => setState(() => _hideAmount = v ?? false),
                      activeColor: const Color(0xFF10B981),
                      side: const BorderSide(color: Color(0xFF475569)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Don\'t show my donation amount',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
          ),
          if (_creditError != null) ...[
            const SizedBox(height: 6),
            Text(_creditError!,
                style:
                    const TextStyle(fontSize: 11, color: Color(0xFFF59E0B))),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF64748B),
                    side: BorderSide(color: AppColors.borderColor(context)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  onPressed: _creditBusy
                      ? null
                      : () => setState(() => _creditSkipped = true),
                  child: const Text('NO THANKS',
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: const Color(0xFF090D10),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  onPressed: _creditBusy ? null : _submitCredit,
                  child: _creditBusy
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF090D10)))
                      : const Text('POST TO WALL',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _wallCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgNested(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: child,
    );
  }

  InputDecoration _creditInputDecoration(String hint, IconData icon) {
    return InputDecoration(
      prefixIcon: Icon(icon, size: 16, color: const Color(0xFF475569)),
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 13),
      counterText: '',
      filled: true,
      fillColor: const Color(0xFF131A20),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.borderColor(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF10B981)),
      ),
      isDense: true,
    );
  }

  /// Compact donors-wall preview under the form (or the saved badge).
  Widget? _buildWallPreview() {
    final wall = _wall;
    if (wall == null || wall.isEmpty) return null;
    return _wallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.favorite_rounded, color: Color(0xFFEF4444), size: 14),
              SizedBox(width: 6),
              Text(
                'RECENT SUPPORTERS',
                style: TextStyle(
                    fontSize: 11.0,
                    letterSpacing: 1,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...wall.take(5).map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        ((c['name'] as String?) ?? '?')
                            .characters
                            .first
                            .toUpperCase(),
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (c['name'] as String?) ?? 'Anonymous',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary(context)),
                          ),
                          if (c['amount'] != null)
                            Text(
                              _wallAmountLabel(c['amount'] as Map<String, dynamic>),
                              style: const TextStyle(
                                  fontSize: 11.0, color: Color(0xFF10B981)),
                            ),
                          if (c['message'] != null)
                            Text(
                              c['message'] as String,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF94A3B8),
                                  height: 1.3),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  String _wallAmountLabel(Map<String, dynamic> amount) {
    final usdCents = (amount['usdCents'] as num?)?.toInt() ?? 0;
    final local = amount['localMinor'] as num?;
    final currency = amount['currency'] as String?;
    final usd =
        '\$${(usdCents / 100).toStringAsFixed(usdCents % 100 == 0 ? 0 : 2)}';
    if (currency != null && local != null) {
      return '${_currencyLabel(currency, local)} · $usd';
    }
    return usd;
  }

  String _currencyLabel(String code, num minor) {
    const symbols = {
      'PHP': '₱', 'EUR': '€', 'GBP': '£', 'JPY': '¥', 'KRW': '₩',
      'INR': '₹', 'CAD': 'CA\$', 'AUD': 'A\$', 'SGD': 'S\$',
    };
    final symbol = symbols[code] ?? '$code ';
    final value = minor / 100;
    return '$symbol${value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2)}';
  }
}
