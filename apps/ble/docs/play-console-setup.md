# Play Console setup for in-app donations

The app's donation modal uses **Google Play Billing** when it detects it was
installed from the Play Store (the donation products resolve). Follow these
steps once, in order, before publishing to the store.

## 1. Create the donation products

Play Console → your app → **Monetize → Products → In-app products** →
**Create product** — five times:

| Product ID        | Type             | Price  | Name (suggestion)   |
| ----------------- | ---------------- | ------ | ------------------- |
| `donation_tier_3` | Managed product  | $3.00  | Supporter           |
| `donation_tier_5` | Managed product  | $5.00  | Supporter Plus      |
| `donation_tier_10`| Managed product  | $10.00 | Champion            |
| `donation_tier_25`| Managed product  | $25.00 | Guardian            |
| `donation_tier_50`| Managed product  | $50.00 | Founding supporter  |

Notes:
- Product IDs must match exactly — they are hardcoded in the app's
  `donation_platform.dart` and verified server-side in `playVerification.ts`.
- "Managed product" is Google's current term for one-time purchases
  (previously "non-consumable"). The app treats every purchase as
  acknowledge-only and never restores/re-buys, which is the compliant
  pattern for tip-style donations.
- Prices can be localized per market by Play; the app displays whatever
  price Play returns for the user's region.

## 2. (Recommended) Link a service account for purchase verification

Without this step, Play purchases still work — the donor just can't post an
optional credit to the public donors wall until it's configured (the API
returns 503 and the app shows a graceful message).

1. Go to **Play Console → Setup → API access** and choose *Create a new
   service account* (Google Cloud console opens).
2. In Cloud, create the service account, then back in Play Console link it
   and grant it the **View financial data** role (that's the least-privileged
   role that can read purchase tokens).
3. Create a JSON key for the service account and download it.
4. On the deploy VM, upload the two values the API needs:

   ```bash
   npx wrangler secret put PLAY_SERVICE_ACCOUNT_CLIENT_EMAIL
   # paste: the service account's ...@...iam.gserviceaccount.com email

   npx wrangler secret put PLAY_SERVICE_ACCOUNT_PRIVATE_KEY
   # paste: the full private key INCLUDING the -----BEGIN/END----- lines
   # (replace literal \n sequences with real newlines)
   ```

5. Redeploy the API if it was already running (`npx wrangler deploy`) —
   secrets bind at deploy time.

## 3. Testing before going live

- Play Console → **Testing → Internal testing**: add your own Gmail as a
  tester, upload the AAB/APK, and run a real purchase (testers' purchases
  are real charges but can be refunded within the console).
- The donor-wall credit path can be verified by submitting the optional
  form after the test purchase — the entry should appear on
  `jkbmsr.com/donations` within seconds.

## What the app does, in order

1. On opening the donate modal, the app queries Play Billing for the five
   product IDs above.
2. **Products resolve** → store install → native Play purchase sheet for the
   chosen tier → purchase token posted to `/ble/donate/play-credit` →
   server-side verification via the Google Android Publisher API.
3. **Products don't resolve** (sideloaded APK, no Play services, or product
   IDs not yet created) → Polar embedded card checkout fallback — allowed
   because sideloaded distribution isn't covered by store policy.
4. Either path can post an optional, privacy-respecting credit to the
   donors wall.
