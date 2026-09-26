import 'dart:async';

import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

import 'package:jkbmsr_ble/services/entitlement_service.dart';

/// A no-op Google Play Billing double so entitlement tests run on the Dart VM
/// (there is no emulator here, and `InAppPurchase` has no implementation off a
/// device — `InAppPurchasePlatform.instance` is `late` and would throw).
///
/// Everything the entitlement code touches is scriptable:
///
///  * [available] — what `isAvailable()` reports (the "Play is missing/offline"
///    case);
///  * [ownedProductIds] — what a `restorePurchases()` re-delivers;
///  * [productDetails] — what `queryProductDetails()` resolves (an empty list
///    models "the Supporter product isn't published yet");
///  * [purchaseUpdates] — pushed explicitly, to model a purchase completing
///    while the app is already running;
///  * [restoresAnswer] — false models a store that never answers, which must
///    time out into "not entitled" rather than hang the app.
///
/// It also records every billing call the app makes, so a test can assert the
/// things that must never happen: no billing call at all in a sideloaded copy,
/// and no `buyConsumable` (which would revoke a non-consumable) anywhere.
final class FakeInAppPurchasePlatform extends InAppPurchasePlatform {
  FakeInAppPurchasePlatform();

  /// Product ids this "account" already owns.
  Set<String> ownedProductIds = <String>{};

  /// What `queryProductDetails()` resolves. Empty = the product isn't live yet.
  List<ProductDetails> productDetails = <ProductDetails>[];

  /// Whether `isAvailable()` reports the store as usable.
  bool available = true;

  /// When false, `restorePurchases()` resolves without ever delivering a
  /// purchase batch (a wedged/offline store).
  bool restoresAnswer = true;

  /// When true, `restorePurchases()` throws instead of answering.
  bool restoreThrows = false;

  /// When true, `isAvailable()` throws instead of answering.
  bool isAvailableThrows = false;

  /// When true, `purchaseStream` throws on access (a platform with no billing
  /// at all).
  bool streamThrows = false;

  /// What `buyNonConsumable()` returns — false models Play refusing to start.
  bool buyNonConsumableSucceeds = true;

  final StreamController<List<PurchaseDetails>> _purchases =
      StreamController<List<PurchaseDetails>>.broadcast();

  int isAvailableCalls = 0;
  int queryProductDetailsCalls = 0;
  int restorePurchasesCalls = 0;
  int buyNonConsumableCalls = 0;
  int buyConsumableCalls = 0;
  int completePurchaseCalls = 0;

  /// Product ids the app asked to buy, in order.
  final List<String> boughtProductIds = <String>[];

  /// Product ids the app acknowledged (via `completePurchase`).
  final List<String> acknowledgedProductIds = <String>[];

  /// True when the app made no billing call whatsoever.
  bool get madeNoBillingCalls =>
      isAvailableCalls == 0 &&
      queryProductDetailsCalls == 0 &&
      restorePurchasesCalls == 0 &&
      buyNonConsumableCalls == 0 &&
      buyConsumableCalls == 0 &&
      completePurchaseCalls == 0;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream {
    if (streamThrows) throw StateError('no billing on this platform');
    return _purchases.stream;
  }

  @override
  Future<bool> isAvailable() async {
    isAvailableCalls++;
    if (isAvailableThrows) throw StateError('billing service unavailable');
    return available;
  }

  @override
  Future<ProductDetailsResponse> queryProductDetails(
      Set<String> identifiers) async {
    queryProductDetailsCalls++;
    final matched = productDetails
        .where((p) => identifiers.contains(p.id))
        .toList(growable: false);
    return ProductDetailsResponse(
      productDetails: matched,
      notFoundIDs:
          identifiers.difference(matched.map((p) => p.id).toSet()).toList(),
    );
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restorePurchasesCalls++;
    if (restoreThrows) {
      throw InAppPurchaseException(
        source: 'fake',
        code: 'restore_failed',
        message: 'restore failed',
      );
    }
    if (!restoresAnswer) return;
    // Exactly what the Android plugin does: re-deliver every purchase this
    // account still owns, flagged as restored.
    scheduleMicrotask(() {
      if (_purchases.isClosed) return;
      _purchases.add([
        for (final id in ownedProductIds)
          supporterPurchase(id, status: PurchaseStatus.restored),
      ]);
    });
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    buyNonConsumableCalls++;
    boughtProductIds.add(purchaseParam.productDetails.id);
    return buyNonConsumableSucceeds;
  }

  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) async {
    buyConsumableCalls++;
    boughtProductIds.add(purchaseParam.productDetails.id);
    return buyNonConsumableSucceeds;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completePurchaseCalls++;
    acknowledgedProductIds.add(purchase.productID);
  }

  /// Model Play reporting a purchase while the app is already running (the
  /// sheet was launched by `buySupporter()`).
  void emitPurchase(String productId, {PurchaseStatus status = PurchaseStatus.purchased}) {
    if (_purchases.isClosed) return;
    _purchases.add([supporterPurchase(productId, status: status)]);
  }

  Future<void> close() => _purchases.close();
}

/// A purchase for [productId] as the Play plugin would hand it over.
PurchaseDetails supporterPurchase(
  String productId, {
  PurchaseStatus status = PurchaseStatus.purchased,
}) {
  return PurchaseDetails(
    purchaseID: 'fake-$productId',
    productID: productId,
    transactionDate: '1757000000000',
    status: status,
    verificationData: PurchaseVerificationData(
      localVerificationData: 'fake-local',
      serverVerificationData: 'fake-server-token',
      source: 'test',
    ),
  );
}

/// A resolved `remove_ads_lifetime` product, as Play would return it.
ProductDetails supporterProduct({
  String id = kRemoveAdsProductId,
  String price = r'$4.99',
}) {
  return ProductDetails(
    id: id,
    title: 'Supporter — remove ads',
    description: 'One-time purchase. Removes ads for good.',
    price: price,
    rawPrice: 4.99,
    currencyCode: 'USD',
  );
}
