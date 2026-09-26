#!/usr/bin/env python3
"""Creates the BLE app's donation in-app products in Google Play Console.

Usage:
  create_donation_products.py [--package-name com.jkbmsr.ble] [--dry-run]

Auth: reads the service account JSON from the GOOGLE_PLAY_SERVICE_ACCOUNT_JSON
env var (raw JSON content, not a path) — same convention as
jkbmsr-pro/scripts/upload_to_play_console.py. The service account must be linked
in Play Console with product-management access to the app.

Products: donation_tier_3/5/10/25/50 at USD 3/5/10/25/50. They are one-time
"managed products"; the app purchases them with buyConsumable(), so a user can
donate repeatedly.

Idempotent: a product that already exists is left untouched (its price is NOT
overwritten), so re-running never clobbers a manual price change.
"""
import argparse
import json
import os
import sys

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

SCOPES = ["https://www.googleapis.com/auth/androidpublisher"]

# (sku, USD amount) — mirrors the IDs in lib/widgets/donate_modal.dart.
DONATION_TIERS = [
    ("donation_tier_3", 3),
    ("donation_tier_5", 5),
    ("donation_tier_10", 10),
    ("donation_tier_25", 25),
    ("donation_tier_50", 50),
]

# The standalone app's Android applicationId (android/app/build.gradle). Note
# this is NOT the stale `com.jkbmsr.jkbmsr_ble` Firebase client that still sits
# in jkbmsr-pro's google-services.json.
DEFAULT_PACKAGE_NAME = "com.jkbmsr.ble"


def product_body(package_name: str, sku: str, amount_usd: int) -> dict:
    micros = str(amount_usd * 1_000_000)
    return {
        "packageName": package_name,
        "sku": sku,
        "status": "active",
        "defaultPrice": {"priceMicros": micros, "currency": "USD"},
        "prices": {"US": {"priceMicros": micros, "currency": "USD"}},
        "listings": {
            "en-US": {
                "title": f"Donation ${amount_usd}",
                "description": f"Support JKBMSR development with a one-time ${amount_usd} donation.",
            }
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-name", default=DEFAULT_PACKAGE_NAME)
    parser.add_argument("--dry-run", action="store_true", help="Print what would be created, call nothing")
    args = parser.parse_args()

    if args.dry_run:
        for sku, amount in DONATION_TIERS:
            print(f"would create {sku} (USD {amount}) in {args.package_name}")
        return 0

    raw_key = os.environ.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")
    if not raw_key:
        print("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is not set", file=sys.stderr)
        return 1

    credentials = service_account.Credentials.from_service_account_info(json.loads(raw_key), scopes=SCOPES)
    service = build("androidpublisher", "v3", credentials=credentials, cache_discovery=False)
    products = service.inappproducts()

    failures = 0
    for sku, amount in DONATION_TIERS:
        try:
            products.get(packageName=args.package_name, sku=sku).execute()
            print(f"skip   {sku} — already exists (price left as-is)")
            continue
        except HttpError as error:
            if error.resp.status != 404:
                print(f"FAIL   {sku} — could not check existence: {error}", file=sys.stderr)
                failures += 1
                continue

        try:
            products.insert(packageName=args.package_name, body=product_body(args.package_name, sku, amount)).execute()
            print(f"create {sku} — USD {amount}")
        except HttpError as error:
            print(f"FAIL   {sku} — {error}", file=sys.stderr)
            failures += 1

    if failures:
        print(f"\n{failures} product(s) failed.", file=sys.stderr)
        return 1
    print("\nDone.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
