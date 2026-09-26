# `remove_ads_lifetime` — the Supporter unlock (Play Console setup)

The BLE app ships two behaviours, and this document is the durable spec for the
one that costs money.

- **JKBMSR BLE Free** — may show ads, once ads are configured (see
  `lib/services/ads_config.dart`; they are **not** configured today).
- **JKBMSR BLE Supporter** — ad-free, permanently, by owning one Google Play
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
| Description          | Removes ads from JKBMSR BLE permanently. One payment, not a subscription. |

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

## 4. Sideload-only payment methods (GCash / QRPh)

`lib/widgets/support_modal.dart` shows a QRPh "Send Support" card **only in a
sideloaded build**. In a Play-managed build the card is not rendered at all.

That is a hard policy constraint, not a preference:

- **[Payments policy](https://support.google.com/googleplay/android-developer/answer/9858738)** —
  "Play-distributed apps requiring or accepting payment for access to in-app
  features or services … must use Google Play's billing system for those
  transactions", and an app "may not lead users to a payment method other than
  Google Play's billing system", explicitly including via "in-app promotions",
  "buttons, links, messaging" and any other "calls to action".
- **[Understanding Google Play's Payments policy](https://support.google.com/googleplay/android-developer/answer/10281818)** —
  the same prohibition restated, and it also covers "directly linking to a
  webpage that could lead to a payment method prohibited by the Payments
  policy".

The peer-to-peer / tax-exempt-donation carve-out does exist, and it is the
reason a *pure tip* can be argued about at all — but it is unavailable to this
app's Play build:

- `remove_ads_lifetime` grants a digital benefit inside the app, so it is not a
  peer-to-peer payment. Selling *that* through an external QR would be
  precisely the prohibited case.
- The only alternative-billing routes are opt-in, regional programs —
  [alternative billing in the EEA](https://support.google.com/googleplay/android-developer/answer/12348241),
  the [external payments program (Japan)](https://support.google.com/googleplay/android-developer/answer/16787536),
  and the US programmes announced for December 2025. They require enrolment,
  user-facing disclosures, transaction reporting, Play Billing 8.3+ APIs and
  service fees. **This app is not enrolled in any of them**, so none of them
  apply and the default rule stands.

Consequences to keep in mind when editing:

- The gate reads `EntitlementService.installKind`, whose Play-vs-sideload
  decision is `SelfUpdate.isPlayManagedInstall` — one definition, shared with
  the in-app self-update. Do not re-test `'com.android.vending'` anywhere else.
- An unresolved install channel (`InstallKind.unknown`) is treated as *not*
  sideloaded, so the QR card stays hidden until Play-managed-ness is actually
  established. Showing an external payment method on an unproven channel is the
  risky direction.
- The donors-wall link (`https://jkbmsr.com/donations`) is a read-only page
  listing public credits and remains available in every build. It takes no
  payment, so it is not a call to action to an alternative payment method.
  Keep it that way: adding a "pay at checkout" link to that flow would change
  its status.

## 5. Turning ads on later (not now)

Ads stay off until an AdMob application id exists for `com.jkbmsr.ble`. There
is deliberately no placeholder id — an AdMob SDK initialises against a
malformed id rather than failing loudly, so a fake value would ship as a
silent runtime failure.

To enable, in this order:

1. Create the AdMob app for `com.jkbmsr.ble` and a banner ad unit.
2. Add the Google Mobile Ads dependency and put the real ids in
   `AdsConfig.current` (`admobAppId`, plus an ad-unit id).
3. Flip `AdsConfig.isConfigured` and `AdsConfig.enabledInThisBuild`.
4. Replace the placeholder in `AdSlot._buildAd` with the SDK's widget.
5. Re-check §4: the GCash/QRPh gate and this change are independent, and the
   Support sheet's "free and ad-free" copy switches branches on
   `AdsConfig.current.isConfigured`.

`AdSlot` is the only widget allowed to render an ad, and it is currently
placed on exactly two read-only surfaces (`StatusScreen`, `CellsScreen`). It
must not be added to the Connect/Scanning flow, the Control screen, the PIN
dialog, or anything shown while a BLE connection is being established.

## 6. Test purchases

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
