# Play Console setup

The in-app donation flow was removed: the app is **ads-only**. There are no
donation products to create and no donation checkout of any kind — the old
Polar embedded card checkout was retired earlier, and the Google Play donation
tiers were removed with it.

The only product this app sells is the one-time Supporter unlock
(`remove_ads_lifetime`) that removes ads. Its Play Console setup is documented
in [`remove-ads-lifetime-setup.md`](remove-ads-lifetime-setup.md).

## What is deliberately absent

- **No donation in-app products** (`donation_tier_3/5/10/25/50`). Do not
  recreate them; nothing in the app references them any more.
- **No external payment method and no checkout surface.** The GCash/QRPh "Send
  Support" card that used to render in a sideloaded build was removed with the
  donation flow.
- **No purchase-verification service account is required** for the ads model.
  `remove_ads_lifetime` is a Play non-consumable verified by Play's own
  ownership query, with no server round-trip.
