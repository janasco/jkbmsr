// Entitlement decision table, as executable code.
//
// There is no Android emulator on this box, so the whole table is driven
// through a scripted `InAppPurchasePlatform` double plus an injected installer
// store — the same no-op-platform trick the existing tests use for
// flutter_blue_plus (see test/support/fake_flutter_blue_plus.dart).
//
//   build        | owns remove_ads_lifetime | ad-free
//   -------------|--------------------------|--------
//   sideloaded   | n/a (no billing call)    | yes
//   Play         | yes                      | yes
//   Play         | no                       | no
//   Play         | unknown/unreachable      | no
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

import 'package:jkbmsr_ble/services/entitlement_service.dart';

import 'support/fake_in_app_purchase.dart';
import 'support/entitlement_test_harness.dart';

/// The double the current test installed, so a case can assert on the calls the
/// app made.
FakeInAppPurchasePlatform billing() =>
    InAppPurchasePlatform.instance as FakeInAppPurchasePlatform;

void main() {
  group('sideloaded build', () {
    test('is ad-free and never calls Google Play', () async {
      // Even an owned unlock must not matter here: a sideloaded copy is
      // ad-free by product decision, not by purchase.
      final entitlements = installFakePlayBilling(
        installedByPlay: false,
        ownedProductIds: {kRemoveAdsProductId},
      );

      expect(await entitlements.isAdFree, isTrue);
      expect(entitlements.installKind, InstallKind.sideload);
      expect(entitlements.supportsPlayPurchases, isFalse);
      expect(billing().madeNoBillingCalls, isTrue,
          reason: 'a sideloaded copy has no Play account; it must not call it');
    });
  });

  group('Google Play build', () {
    test('with the non-consumable owned is ad-free', () async {
      final entitlements = installFakePlayBilling(
        installedByPlay: true,
        ownedProductIds: {kRemoveAdsProductId},
      );

      expect(await entitlements.isAdFree, isTrue);
      expect(entitlements.installKind, InstallKind.play);
      expect(entitlements.installKind.isPlayManaged, isTrue);
    });

    test('with nothing owned is not entitled', () async {
      final entitlements = installFakePlayBilling(installedByPlay: true);

      expect(await entitlements.isAdFree, isFalse);
      expect(entitlements.state.resolved, isTrue,
          reason: '"not entitled" must be a resolved answer, not "not yet"');
    });

    test('ignores an unrelated non-consumable', () async {
      final entitlements = installFakePlayBilling(
        installedByPlay: true,
        ownedProductIds: {'some_other_unlock'},
      );

      expect(await entitlements.isAdFree, isFalse);
    });

    test('an unavailable billing service is not entitled and does not throw',
        () async {
      final entitlements = installFakePlayBilling(
        installedByPlay: true,
        available: false,
      );

      expect(await entitlements.isAdFree, isFalse);
    });

    test('a throwing billing service is not entitled and does not throw',
        () async {
      final entitlements = installFakePlayBilling(
        installedByPlay: true,
        isAvailableThrows: true,
      );

      expect(await entitlements.isAdFree, isFalse);
    });

    test('a throwing restore is not entitled and does not throw', () async {
      final entitlements = installFakePlayBilling(
        installedByPlay: true,
        restoreThrows: true,
      );

      expect(await entitlements.isAdFree, isFalse);
    });

    test('a platform with no purchase stream is not entitled', () async {
      final entitlements = installFakePlayBilling(
        installedByPlay: true,
        streamThrows: true,
      );

      expect(await entitlements.isAdFree, isFalse);
    });

    // The one case that costs real time: it is the only way to prove the
    // startup wait is actually bounded, which is what keeps a wedged Play
    // Store from holding the app on a splash screen.
    test('a store that never answers times out into "not entitled"', () async {
      final entitlements = installFakePlayBilling(
        installedByPlay: true,
        restoresAnswer: false,
      );

      final stopwatch = Stopwatch()..start();
      final adFree = await entitlements.isAdFree;
      stopwatch.stop();

      expect(adFree, isFalse, reason: 'fail safe: show ads rather than guess');
      expect(stopwatch.elapsed, lessThan(EntitlementService.billingTimeout * 2),
          reason: 'startup must not be blocked indefinitely');
      expect(entitlements.state.resolved, isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('resolve()', () {
    test('is idempotent and still resolves the entitlement', () async {
      final entitlements = installFakePlayBilling(
        installedByPlay: true,
        ownedProductIds: {kRemoveAdsProductId},
      );

      await entitlements.resolve();
      final callsAfterFirst = billing().restorePurchasesCalls;

      await entitlements.resolve();
      expect(billing().restorePurchasesCalls, callsAfterFirst,
          reason: 'a second resolve() must not re-hit the store');
      expect(entitlements.isAdFreeNow, isTrue);
    });
  });

  group('restorePurchases()', () {
    test('applies the entitlement the Play account already owns', () async {
      final entitlements = installFakePlayBilling(installedByPlay: true);
      await entitlements.resolve();
      expect(entitlements.isAdFreeNow, isFalse);

      // A supporter who reinstalled on a new device: nothing is owned at
      // startup, then the purchase turns up.
      billing().ownedProductIds = {kRemoveAdsProductId};

      expect(await entitlements.restorePurchases(), RestoreStatus.restored);
      expect(entitlements.isAdFreeNow, isTrue);
      expect(await entitlements.isAdFree, isTrue);
    });

    test('reports notEntitled when the account owns nothing', () async {
      final entitlements = installFakePlayBilling(installedByPlay: true);
      await entitlements.resolve();

      expect(await entitlements.restorePurchases(), RestoreStatus.notEntitled);
      expect(entitlements.isAdFreeNow, isFalse);
    });

    test('reports unavailable when Play cannot be reached', () async {
      final entitlements =
          installFakePlayBilling(installedByPlay: true, available: false);
      await entitlements.resolve();

      expect(await entitlements.restorePurchases(), RestoreStatus.unavailable);
      expect(entitlements.isAdFreeNow, isFalse);
    });

    test('is a no-op with its own answer in a sideloaded copy', () async {
      final entitlements = installFakePlayBilling(installedByPlay: false);
      await entitlements.resolve();

      expect(await entitlements.restorePurchases(), RestoreStatus.notApplicable);
      expect(billing().restorePurchasesCalls, 0);
      expect(entitlements.isAdFreeNow, isTrue);
    });
  });

  group('Supporter purchase', () {
    test('buys a non-consumable, never a consumable', () async {
      final entitlements = installFakePlayBilling(
        installedByPlay: true,
        products: [supporterProduct()],
      );
      await entitlements.resolve();

      expect(await entitlements.buySupporter(), BuyStatus.started);
      expect(billing().buyNonConsumableCalls, 1);
      expect(billing().buyConsumableCalls, 0,
          reason: 'a consumed non-consumable is dropped from Play\'s ownership '
              'query, which would silently revoke the unlock');
      expect(billing().boughtProductIds, [kRemoveAdsProductId]);
    });

    test('acknowledges (never consumes) the unlock Play reports back',
        () async {
      final entitlements = installFakePlayBilling(installedByPlay: true);
      await entitlements.resolve();
      expect(entitlements.isAdFreeNow, isFalse);

      // The Play sheet completed while the app is already running.
      billing().emitPurchase(kRemoveAdsProductId);
      await Future<void>.delayed(Duration.zero);

      expect(entitlements.isAdFreeNow, isTrue);
      expect(billing().completePurchaseCalls, 1);
      expect(billing().acknowledgedProductIds, [kRemoveAdsProductId]);
      expect(billing().buyConsumableCalls, 0);
    });

    test('reports unavailable while the product is not published', () async {
      final entitlements = installFakePlayBilling(installedByPlay: true);
      await entitlements.resolve();

      expect(await entitlements.buySupporter(), BuyStatus.unavailable);
    });

    test('is unavailable in a sideloaded copy and calls nothing', () async {
      final entitlements = installFakePlayBilling(installedByPlay: false);
      await entitlements.resolve();

      expect(await entitlements.buySupporter(), BuyStatus.unavailable);
      expect(billing().madeNoBillingCalls, isTrue);
    });
  });

  group('supporterPrice()', () {
    test('returns the localized price Play resolves', () async {
      final entitlements = installFakePlayBilling(
        installedByPlay: true,
        products: [supporterProduct(price: '€4,99')],
      );
      await entitlements.resolve();

      expect(await entitlements.supporterPrice(), '€4,99');
    });

    test('is null when the product does not resolve', () async {
      final entitlements = installFakePlayBilling(installedByPlay: true);
      await entitlements.resolve();

      expect(await entitlements.supporterPrice(), isNull);
    });
  });

  group('entitlement changes are observable', () {
    test('the notifier fires when the entitlement resolves', () async {
      final entitlements = installFakePlayBilling(
        installedByPlay: true,
        ownedProductIds: {kRemoveAdsProductId},
      );

      final seen = <EntitlementState>[];
      entitlements.changes.addListener(() => seen.add(entitlements.state));

      await entitlements.resolve();

      expect(seen, isNotEmpty, reason: 'the UI has to be able to rebuild');
      expect(seen.last.adFree, isTrue);
      expect(entitlements.changes.value.adFree, isTrue);
    });
  });
}
