import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

import 'package:jkbmsr_ble/services/entitlement_service.dart';

import 'fake_in_app_purchase.dart';

/// Installs a scripted Google Play Billing double and hands back a fresh
/// [EntitlementService] wired to it.
///
/// The install channel is injected rather than read from PackageInfo (there is
/// no Android package manager on the Dart VM), which is also how the real
/// build's single "is this a Play copy?" decision stays the only one: the
/// service still funnels it through [SelfUpdate.isPlayManagedInstall].
///
/// Pass [installedByPlay: false] for a sideloaded copy. It is also where
/// "Google Play answered but owns nothing" and "Google Play never answered"
/// are modelled, so every row of the entitlement decision table is reachable
/// without a device.
EntitlementService installFakePlayBilling({
  required bool installedByPlay,
  Set<String> ownedProductIds = const <String>{},
  bool available = true,
  bool restoresAnswer = true,
  bool restoreThrows = false,
  bool isAvailableThrows = false,
  bool streamThrows = false,
  List<ProductDetails> products = const <ProductDetails>[],
}) {
  final billing = FakeInAppPurchasePlatform()
    ..ownedProductIds = {...ownedProductIds}
    ..available = available
    ..restoresAnswer = restoresAnswer
    ..restoreThrows = restoreThrows
    ..isAvailableThrows = isAvailableThrows
    ..streamThrows = streamThrows
    ..productDetails = [...products];

  // Materialise the cached `InAppPurchase` singleton. Its one-time platform
  // registration happens on first access (and only for android/iOS/macOS) and
  // would clobber the double — so that read happens with the test target
  // pinned to a platform that registers nothing. The override is scoped to
  // this single statement: the framework asserts it is unset at the end of a
  // widget test, and a real Android registration would also start a
  // BillingClientManager whose async connect has no platform channel here.
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  try {
    expect(InAppPurchase.instance, isNotNull);
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }

  InAppPurchasePlatform.instance = billing;
  addTearDown(() async {
    InAppPurchasePlatform.instance = billing;
    await billing.close();
  });

  return EntitlementService(
    installerStoreReader: () async =>
        installedByPlay ? 'com.android.vending' : 'org.fdroid.fdroid',
  );
}
