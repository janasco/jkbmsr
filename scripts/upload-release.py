#!/usr/bin/env python3
"""Uploads a release artifact to the api.jkbmsr.com release endpoint.

The Worker (`jkbmsr-cloud`) exposes POST /ble/release and POST /mobile/release
(see backend/src/routes/releases.ts). They authenticate with a per-product
bearer upload secret and accept the artifact as the raw request body, with
version/sha256 in the query string — the streamed encoding, not multipart,
so the Worker's memory stays flat for 55MB+ APKs.

This replaces the previous `curl --data-binary` call in the apps'
publish-release.sh scripts: curl is unusable on some build hosts, and the
Python standard library is always present.

Usage:
  upload-release.py --url https://api.jkbmsr.com/ble/release \
      --version 4.17.20 --sha256 <hex> --file path/to/app.apk \
      --secret-env BLE_RELEASE_UPLOAD_SECRET

The secret is read from the named environment variable (never taken as an
argument, so it cannot leak into the process list). Exit status mirrors
`curl --fail-with-body`: non-zero on any HTTP >= 400 or transport error.
"""
import argparse
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", required=True, help="Release endpoint, e.g. https://api.jkbmsr.com/ble/release")
    parser.add_argument("--version", required=True, help="Version number without a 'v' prefix")
    parser.add_argument("--sha256", required=True, help="SHA-256 of the artifact being uploaded")
    parser.add_argument("--file", required=True, help="Path to the artifact to upload")
    parser.add_argument("--secret-env", required=True, help="Name of the environment variable holding the upload secret")
    args = parser.parse_args()

    secret = os.environ.get(args.secret_env, "")
    if not secret:
        print(f"{args.secret_env} is not set", file=sys.stderr)
        return 1
    if not os.path.isfile(args.file):
        print(f"No such file: {args.file}", file=sys.stderr)
        return 1

    query = urllib.parse.urlencode({"version": args.version, "sha256": args.sha256})
    request = urllib.request.Request(
        f"{args.url}?{query}",
        data=open(args.file, "rb"),
        method="POST",
        headers={
            "Authorization": f"Bearer {secret}",
            "Content-Type": "application/vnd.android.package-archive",
            "Content-Length": str(os.path.getsize(args.file)),
            "User-Agent": "jkbmsr-release-script/1.0",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=900) as response:
            print(f"HTTP {response.status}")
            print(response.read().decode("utf-8", "replace"))
            return 0 if response.status < 400 else 1
    except urllib.error.HTTPError as error:
        print(f"HTTP {error.code}")
        print(error.read().decode("utf-8", "replace"), file=sys.stderr)
        return 1
    except urllib.error.URLError as error:
        print(f"Upload failed: {error.reason}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
