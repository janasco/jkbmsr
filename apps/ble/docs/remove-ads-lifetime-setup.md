# `remove_ads_lifetime` — the Supporter unlock (Play Console setup)

The BLE app ships two behaviours, and this document is the durable spec for the
one that costs money.

- **JK BMS Local Free** — may show ads; the release builds configure them (see
  `lib/services/ads_config.dart` and `scripts/ads-defines.sh`).
- **JK BMS Local Supporter** — ad-free, permanently, by owning one Google Play
  product.

There is no second app, no "Pro" edition of this app, and no subscription. The
companion `jkbmsr-pro` app is a different product, is permanently ad-free, and
contains no billing code at all.

---

## 1. The product

| Field                | Value                                        |
| -------------------- | -------------------------------------------- |
| Product ID           | `remove_ads_lifetime`                        |
| Product type         | **Non-consumable** (one-time purchase)       |
| Play Console path    | Monetize → Products → **One-time products**  |
| Price                | TBD — pick once; Play localizes it per market |
| Internal name        | Supporter — remove ads                       |
| Description          | Removes ads from JK BMS Local permanently. One payment, not a subscription. |

The product ID is hardcoded once, in `lib/services/entitlement_service.dart`:

```dart
const String kRemoveAdsProductId = 'remove_ads_lifetime';
```

Nothing else in the app may reference the string; a second literal is how a
store product ends up unsellable.

### Why non-consumable and not subscription

- A Supporter pays once. A subscription would need renewal UI, a
  manage-subscription path, and a grace/entitlement state machine for a
  product that grants one permanent thing.
- Play refuses a second purchase of an owned non-consumable, so the entitlement
  cannot be sold twice, and it is returned by Play's ownership query forever.
- It is the only mechanism that survives a new phone with no JKBMSR account: see
  §3.

## 2. Play policy justification (required in the listing/review notes)

Play treats "no ads" as **digital content/functionality delivered in the app**,
so removing it is a digital purchase and must be transacted through Google Play
Billing. The store listing and the in-app description must therefore say all of:

1. The app may display advertisements.
2. A one-time in-app purchase (`remove_ads_lifetime`) removes them.
3. The purchase is not a subscription and does not renew.
4. There is no charge to use the app's BLE monitoring and control features;
   removing ads is a supporter contribution, not a feature unlock.
5. The purchase is tied to the Google Play account and can be re-applied on
   another device with the Support sheet's **Restore purchase** button.

Never describe the product as a "license", a "subscription", or a "premium
version" — it unlocks nothing but the absence of ads.

## 3. How the entitlement is carried (no JKBMSR account required)

The unlock lives **only** in Play's own ownership of the non-consumable. There
is no server-side record, no API call, and no account in the app. A supporter
who reinstalls, buys a new phone, or wipes app data taps **Restore purchase**
in the Support sheet and Play re-delivers the purchase.

Implementation, for reference when editing:

- `EntitlementService.resolve()` — startup. Reads the installer store, and for
  a Play build re-delivers Play's owned purchases with `restorePurchases()`.
  A sideloaded copy is ad-free by policy and never calls Play at all.
- `EntitlementService.restorePurchases()` — the user-initiated **Restore
  purchase** action.
- `EntitlementService.buySupporter()` — calls **`buyNonConsumable`**, never
  `buyConsumable`. A consumed product is dropped from Play's ownership query,
  so consuming the unlock would silently revoke it and let the same account buy
  it again.
- Acknowledgement is `completePurchase()` (acknowledge), which is *not*
  consumption. Nothing in the app calls `consumePurchase`.
- Every Play call is bounded (`EntitlementService.billingTimeout`) and every
  failure resolves to **not entitled**, so a Supporter who is offline sees ads
  again until Play answers. That is deliberate: the alternative — trusting a
  locally cached "I'm a Supporter" flag — would let anyone clear app data and
  get the app for free.

| Build                  | Owns `remove_ads_lifetime` | Ad-free |
| ---------------------- | -------------------------- | ------- |
| sideloaded APK         | n/a — Play is never called | yes     |
| Google Play            | yes                        | yes     |
| Google Play            | no                         | no      |
| Google Play, Play down | unknown                    | no      |

## 4. How ads are enabled (done for 4.17.22+42)

The Google Mobile Ads dependency is present, and both the AdMob app id and the
ads kill switch are **build-time constants** in
`lib/services/ads_config.dart` (`String.fromEnvironment('ADMOB_APP_ID')` and
`bool.fromEnvironment('ADS_ENABLED')`), so enabling ads is a build invocation
rather than a code edit:

```sh
flutter build apk \
  --dart-define=ADMOB_APP_ID=ca-app-pub-…~… \
  --dart-define=ADMOB_BANNER_AD_UNIT_ID=ca-app-pub-…/… \
  --dart-define=ADS_ENABLED=true
```

The real values are public, so they live in `scripts/ads-defines.sh`, which
`scripts/build-play-aab.sh` and `scripts/publish-release.sh` both source. A
build with no such defines stays inert: `AdsConfig.current` is
`isConfigured: false`, `enabledInThisBuild: false`, `admobAppId: null`, and no
ad is ever requested — which is why `flutter test` and a plain `flutter build`
remain silent. There is deliberately no fake id in `AdsConfig`: an AdMob SDK
initialises against a malformed id rather than failing loudly, so a placeholder
there would ship as a silent runtime failure. The Android manifest carries the
real application id (it must be present or a release build crashes), paired
with the same `ADMOB_APP_ID` define.

The checklist that produced this state:

1. Create the AdMob app for `com.jkbmsr.ble` and a banner ad unit. ✅
2. Pass the real app id at build time (`ADMOB_APP_ID=…`) and set
   `ADS_ENABLED=true`. ✅ (via `scripts/ads-defines.sh`)
3. Replace the test `APPLICATION_ID` in the Android manifest with the real one.
   ✅
4. `AdSlot._buildAd` renders the SDK's real banner (`_AdMobBanner`). ✅

`AdSlot` is the only widget allowed to render an ad, and it is currently
placed on exactly two read-only surfaces (`StatusScreen`, `CellsScreen`). It
must not be added to the Connect/Scanning flow, the Control screen, the PIN
dialog, or anything shown while a BLE connection is being established.

## 5. Test purchases

The entitlement is exercised by pure Dart/widget tests, never a device test —
see `test/entitlement_service_test.dart`, `test/ad_slot_test.dart` and
`test/support_modal_test.dart`. They drive a scripted
`InAppPurchasePlatform` double (`test/support/fake_in_app_purchase.dart`) and
cover the whole table in §3, so a Play account is not required to change this
code.

Before shipping, still verify once on a real device: Play Console → **Testing →
Internal testing**, install that build, buy `remove_ads_lifetime`, uninstall,
reinstall, and confirm the app opens ad-free without tapping Restore (Play
re-delivers the owned purchase at launch), then confirm **Restore purchase**
works after clearing app data.
