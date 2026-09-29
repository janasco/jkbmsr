import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'self_update.dart';

/// Play product ID of the Supporter unlock: a one-time (non-consumable)
/// purchase that removes ads for the lifetime of the Google Play account.
///
/// It is deliberately NOT a subscription: a Supporter pays once and keeps the
/// ad-free app forever, and Play itself refuses a second purchase of the same
/// product, so the entitlement is inherently durable.
const String kRemoveAdsProductId = 'remove_ads_lifetime';

/// How this copy of the app was obtained.
///
/// The single source of truth for "sideload vs Google Play" is
/// [SelfUpdate.isPlayManagedInstall] — the same helper the in-app self-update
/// uses. Nothing else in the app re-implements the check.
enum InstallKind {
  /// Android reported `com.android.vending` as the installer: this copy came
  /// from Google Play, so Play Billing is the only payment path available.
  play,

  /// Any other installer (adb, F-Droid, an APK from the website, an Amazon
  /// store copy). There is no Play account behind it, so Play Billing cannot
  /// answer anything.
  sideload,

  /// [EntitlementService.resolve] has not finished yet. Treated as "not
  /// Play-managed" for the entitlement and as "Play" for anything that must
  /// not be shown on the strength of an unproven assumption.
  unknown;

  /// True only once Google Play is positively known to be the distributor.
  bool get isPlayManaged => this == InstallKind.play;
}

/// Immutable snapshot of who this user is and whether ads may show.
@immutable
class EntitlementState {
  const EntitlementState({
    this.installKind = InstallKind.unknown,
    this.adFree = false,
    this.resolved = false,
  });

  final InstallKind installKind;

  /// Fail-safe: true only on positive evidence — a sideloaded copy, or a
  /// Supporter purchase owned by the Play account behind this install.
  final bool adFree;

  /// True once [EntitlementService.resolve] has produced a final answer, so
  /// the UI can tell "resolved: no entitlement" from "not looked yet".
  final bool resolved;

  EntitlementState copyWith({
    InstallKind? installKind,
    bool? adFree,
    bool? resolved,
  }) =>
      EntitlementState(
        installKind: installKind ?? this.installKind,
        adFree: adFree ?? this.adFree,
        resolved: resolved ?? this.resolved,
      );

  // Value equality so the ValueNotifier below doesn't notify the UI when a
  // re-resolve lands on the same answer.
  @override
  bool operator ==(Object other) =>
      other is EntitlementState &&
      other.installKind == installKind &&
      other.adFree == adFree &&
      other.resolved == resolved;

  @override
  int get hashCode => Object.hash(installKind, adFree, resolved);

  @override
  String toString() => 'EntitlementState(installKind: ${installKind.name}, adFree: $adFree, '
      'resolved: $resolved)';
}

/// Outcome of a user-initiated "Restore purchase".
enum RestoreStatus {
  /// The Play account owns the Supporter unlock; it has been applied.
  restored,

  /// Google Play answered, and this account owns no Supporter unlock.
  notEntitled,

  /// Play Billing could not be reached (offline, no Play services, timed out).
  unavailable,

  /// Nothing to restore: this copy was not installed by Google Play.
  notApplicable,
}

/// Human-readable copy for a [RestoreStatus]. Kept next to the enum so no
/// screen can invent a different promise for the same outcome.
extension RestoreStatusMessage on RestoreStatus {
  String get message {
    switch (this) {
      case RestoreStatus.restored:
        return 'Supporter restored — ads are off.';
      case RestoreStatus.notEntitled:
        return 'No Supporter purchase on this Google Play account.';
      case RestoreStatus.unavailable:
        return 'Could not reach Google Play. Try again when you are online.';
      case RestoreStatus.notApplicable:
        return 'This copy was not installed from Google Play, so it is '
            'already ad-free.';
    }
  }
}

/// Outcome of starting the Supporter purchase. The entitlement itself flips
/// later, when the purchase arrives on the store's purchase stream.
enum BuyStatus {
  /// The Play purchase sheet was launched; the result arrives asynchronously.
  started,

  /// Play Billing, or the Supporter product itself, is not available.
  unavailable,

  /// Play Billing could not be reached.
  failed,
}

/// Lifetime ad-removal entitlement, owned through Google Play.
///
/// Why Play ownership and not a JKBMSR account: the unlock has to survive a
/// new phone, a reinstall and cleared app data for someone who never made a
/// JKBMSR account, and only the store's own non-consumable ownership does
/// that. There is no server round-trip in this class by design.
///
/// Decision table (all of it lands in [EntitlementState.adFree]):
///
/// | Build                | Play account owns `remove_ads_lifetime` | Ad-free |
/// |----------------------|----------------------------------------|---------|
/// | sideloaded           | n/a — Play is never called             | yes     |
/// | Google Play          | yes                                    | yes     |
/// | Google Play          | no                                     | no      |
/// | Google Play          | unknown — Play unreachable/timed out   | no      |
/// | unknown (pre-resolve)| not queried yet                         | no      |
///
/// Every Play call is bounded by [billingTimeout] and every failure degrades
/// to "not entitled": the app must open, and must not crash, when Play is
/// missing, offline or wedged.
class EntitlementService {
  EntitlementService({Future<String?> Function()? installerStoreReader})
      : _readInstallerStore = installerStoreReader ?? _platformInstallerStore;

  /// App-wide instance. `main()` resolves it before the first frame; widgets
  /// read it (never write it).
  static final EntitlementService instance = EntitlementService();

  /// Upper bound on any single Play Billing call, so a slow, offline or
  /// wedged Play Store cannot hold the app hostage on startup.
  static const Duration billingTimeout = Duration(seconds: 6);

  final Future<String?> Function() _readInstallerStore;
  final ValueNotifier<EntitlementState> _state =
      ValueNotifier<EntitlementState>(const EntitlementState());

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  Future<void>? _resolveInFlight;
  ProductDetails? _supporterProduct;

  /// Entitlement changes (install kind, ad-free, resolved) for the UI to
  /// rebuild against.
  ValueListenable<EntitlementState> get changes => _state;

  EntitlementState get state => _state.value;

  InstallKind get installKind => _state.value.installKind;

  /// Current answer without triggering a lookup. Prefer [isAdFree] from async
  /// code; widgets should listen to [changes].
  bool get isAdFreeNow => _state.value.adFree;

  /// True when this copy came from Google Play, so Play Billing is the only
  /// payment path available and external payment methods are off.
  bool get supportsPlayPurchases => installKind.isPlayManaged;

  /// The ad-removal entitlement. Triggers [resolve] on first call, so it is
  /// never a stale pre-resolution `false`; returns `false` (not entitled) on
  /// any failure.
  Future<bool> get isAdFree async {
    await resolve();
    return _state.value.adFree;
  }

  /// Idempotent. Resolves the install channel, then the Play ownership of
  /// [kRemoveAdsProductId]. Never throws, never hangs past
  /// [billingTimeout] per call.
  Future<void> resolve() => _resolveInFlight ??= _resolve();

  Future<void> _resolve() async {
    final kind = await _detectInstallKind();

    // A sideloaded copy is ad-free by product decision and must never touch
    // Play Billing: there is no Play account behind it, so the call could only
    // stall or fail.
    final adFree = kind == InstallKind.sideload || await _ownsSupporterUnlock(kind);

    _publish(state.copyWith(
      installKind: kind,
      adFree: adFree,
      resolved: true,
    ));
  }

  /// User-initiated "Restore purchase": re-reads the unlock from the Play
  /// account, which is the only way a supporter's ad-free app comes back on a
  /// new device without a JKBMSR account.
  Future<RestoreStatus> restorePurchases() async {
    if (!supportsPlayPurchases) return RestoreStatus.notApplicable;
    final iap = InAppPurchase.instance;
    try {
      _listenForPurchases(iap);
      if (!await iap.isAvailable().timeout(billingTimeout)) {
        return RestoreStatus.unavailable;
      }
      final purchases = await _queryPlayOwnership(iap);
      if (!purchases.any(_isSupporterPurchase)) return RestoreStatus.notEntitled;
      // The permanent stream listener has already applied the entitlement and
      // acknowledged the purchase; this is idempotent and only covers the
      // case where the listener had to be attached for the first time here.
      _grantAdFree();
      return RestoreStatus.restored;
    } catch (_) {
      return RestoreStatus.unavailable;
    }
  }

  /// Starts the one-time Supporter purchase.
  ///
  /// Uses `buyNonConsumable`, never `buyConsumable`: a consumed product is
  /// dropped from Play's ownership query, so consuming it would silently
  /// revoke the unlock (and let the same account buy it again, forever).
  Future<BuyStatus> buySupporter() async {
    if (!supportsPlayPurchases) return BuyStatus.unavailable;
    final iap = InAppPurchase.instance;
    try {
      _listenForPurchases(iap);
      if (!await iap.isAvailable().timeout(billingTimeout)) {
        return BuyStatus.unavailable;
      }
      final response = await iap.queryProductDetails({kRemoveAdsProductId}).timeout(billingTimeout);
      final matches = response.productDetails.where((p) => p.id == kRemoveAdsProductId).toList();
      if (matches.isEmpty) return BuyStatus.unavailable;
      _supporterProduct = matches.first;

      final started = await iap
          .buyNonConsumable(
            purchaseParam: PurchaseParam(productDetails: _supporterProduct!),
          )
          .timeout(billingTimeout);
      // The result arrives on the purchase stream, which flips the
      // entitlement; this call only reports whether Play accepted the request.
      return started ? BuyStatus.started : BuyStatus.failed;
    } catch (_) {
      return BuyStatus.failed;
    }
  }

  /// Localized price of the Supporter unlock, or `null` when Play hasn't
  /// published it (or can't be reached). Used for the buy button's label.
  Future<String?> supporterPrice() async {
    if (!supportsPlayPurchases) return null;
    final cached = _supporterProduct;
    if (cached != null) return cached.price;
    final iap = InAppPurchase.instance;
    try {
      if (!await iap.isAvailable().timeout(billingTimeout)) return null;
      final response = await iap.queryProductDetails({kRemoveAdsProductId}).timeout(billingTimeout);
      for (final product in response.productDetails) {
        if (product.id == kRemoveAdsProductId) {
          _supporterProduct = product;
          return product.price;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<InstallKind> _detectInstallKind() async {
    final store = await _readInstallerStore();
    // Google Play is the only installer this app treats as Play-managed, and
    // that decision already exists for the self-update flow. A store that
    // can't be read (no Play/Amazon store installed, a stripped test build)
    // counts as "not Play", matching that existing convention, so the ad and
    // payment gates can never disagree about what kind of build this is.
    return SelfUpdate.isPlayManagedInstall(store) ? InstallKind.play : InstallKind.sideload;
  }

  Future<bool> _ownsSupporterUnlock(InstallKind kind) async {
    if (kind != InstallKind.play) return false;
    final iap = InAppPurchase.instance;
    try {
      // Subscribe before anything else: the plugin re-delivers a purchase
      // that was never acknowledged on the next launch, and a later
      // subscriber would miss that event.
      _listenForPurchases(iap);
      if (!await iap.isAvailable().timeout(billingTimeout)) return false;
      final purchases = await _queryPlayOwnership(iap);
      return purchases.any(_isSupporterPurchase);
    } catch (_) {
      return false; // fail safe: no evidence of a Supporter purchase
    }
  }

  /// Asks Play which purchases this account still owns, and returns them.
  ///
  /// Uses `restorePurchases()` rather than Play's `queryPastPurchases()`
  /// platform addition: it is the public, cross-platform API, and on Android
  /// it is exactly a `queryPurchases()` of non-consumed purchases re-delivered
  /// on the purchase stream. Consumed items are never returned, which is
  /// right — a non-consumable unlock must never be consumed.
  ///
  /// The answer is the first batch delivered on the stream after the
  /// subscription. Any earlier batch (an unacknowledged purchase from the
  /// previous session, say) is a better answer, not a worse one.
  Future<List<PurchaseDetails>> _queryPlayOwnership(InAppPurchase iap) async {
    // The error handler is attached here, at creation, not after the restore
    // call: a store that throws, or a stream that closes without ever
    // answering, must read as "owns nothing" instead of leaving a dangling
    // future that reports an unhandled async error later.
    final batch = iap.purchaseStream.first.then<List<PurchaseDetails>>(
          (purchases) => purchases,
          onError: (Object _) => const <PurchaseDetails>[],
        );
    await iap.restorePurchases().timeout(billingTimeout);
    return batch.timeout(
      billingTimeout,
      onTimeout: () => const <PurchaseDetails>[],
    );
  }

  /// Single purchase-stream subscription for the app. It applies the
  /// entitlement and acknowledges the unlock whenever Play reports it —
  /// bought here, restored, or re-delivered from a previous session.
  ///
  /// Acknowledging is NOT consuming: `completePurchase` tells Play the content
  /// was delivered, and the purchase stays owned so it keeps restoring on a
  /// new device. `consumePurchase` is never called.
  void _listenForPurchases(InAppPurchase iap) {
    if (_purchaseSub != null) return;
    try {
      _purchaseSub = iap.purchaseStream.listen(
        (purchases) {
          final owned = purchases.where(_isSupporterPurchase).toList();
          if (owned.isEmpty) return;
          _grantAdFree();
          unawaited(_acknowledge(iap, owned));
        },
        onError: (Object _) {
          // A store-side error is not a reason to disturb the entitlement; the
          // next restore/launch re-reads ownership.
        },
      );
    } catch (_) {
      // No billing implementation on this platform (or a test double that
      // doesn't provide a stream). The buy/restore paths above then report
      // themselves as unavailable, and the app stays alive and unentitled.
    }
  }

  Future<void> _acknowledge(InAppPurchase iap, List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      try {
        await iap.completePurchase(purchase);
      } catch (_) {
        // Already acknowledged, or the store is unhappy. Never fatal: the
        // entitlement is already applied and ownership persists either way.
      }
    }
  }

  static bool _isSupporterPurchase(PurchaseDetails purchase) =>
      purchase.productID == kRemoveAdsProductId &&
      (purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored);

  void _grantAdFree() {
    if (state.adFree) return;
    _publish(state.copyWith(adFree: true, resolved: true));
  }

  void _publish(EntitlementState next) {
    if (next == state) return;
    _state.value = next;
  }

  static Future<String?> _platformInstallerStore() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.installerStore;
    } catch (_) {
      return null;
    }
  }

  /// Releases the store subscription. Only used by tests and by nothing in the
  /// app: the entitlement is a process-lifetime fact.
  @visibleForTesting
  Future<void> dispose() async {
    await _purchaseSub?.cancel();
    _purchaseSub = null;
    _resolveInFlight = null;
  }

  /// Pins a specific entitlement state so a widget test can render a Play build
  /// or a Supporter without a store. Always pair with [debugResetState] in
  /// tearDown — the app-wide instance is shared.
  @visibleForTesting
  void debugOverrideState(EntitlementState next) => _publish(next);

  /// Back to the unresolved default.
  @visibleForTesting
  void debugResetState() => _publish(const EntitlementState());
}
