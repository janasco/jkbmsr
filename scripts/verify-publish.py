#!/usr/bin/env python3
"""Verify a published Cloudflare Pages deployment with a real HTTP read.

Why this exists
---------------
The natural instinct after a deploy is to read the object back with the same
tool that wrote it — `wrangler r2 object get`, or the deployment URL wrangler
prints. Both can lie:

  * `wrangler r2 object get` defaults to LOCAL storage in recent wrangler
    versions, and it needs the account id in the environment. With a token that
    can see two accounts and no account id, it reads from the wrong account and
    reports a clean match against an object the live edge never received.
  * The URL wrangler prints for a Pages deployment is a deployment-specific
    preview URL, not the custom domain. Reading it proves the upload landed,
    not that `docs.jkbmsr.com` / `cdn.jkbmsr.com` serves it.

So verification is always: GET the public URL over HTTP, hash the bytes, and
compare that hash against the local file that was deployed. This script does
exactly that and nothing else.

`curl` is not used anywhere in this repository — it is broken on the build host
(config parse error: "ORDER: parameter null or not set"). Everything here goes
through the standard library's urllib.

Usage:
  scripts/verify-publish.py --url https://cdn.jkbmsr.com/index.html \
      --file releases/dist/index.html
  scripts/verify-publish.py --url https://cdn.jkbmsr.com/firmware/releases.json \
      --expect-sha256 1a2b3c... --attempts 6 --delay 10

Exit status:
  0  every URL fetched and matched
  1  a URL mismatched, or never matched within the retry budget
  2  usage error
"""

from __future__ import annotations

import argparse
import hashlib
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

USER_AGENT = "jkbmsr-verify-publish/1.0"


def local_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def bust_cache(url: str, salt: str) -> str:
    """Append a cache-busting parameter.

    Pages and the Cloudflare edge both cache aggressively; a verification read
    that can be served from cache proves nothing about the deploy that just
    happened.
    """
    joiner = "&" if "?" in url else "?"
    return f"{url}{joiner}__verify={salt}"


def fetch(url: str, timeout: int) -> tuple[int, bytes, str]:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.status, response.read(), response.geturl()


def verify_one(
    url: str,
    expected_sha256: str | None,
    expected_size: int | None,
    attempts: int,
    delay: int,
    timeout: int,
) -> bool:
    salt = f"{int(time.time())}-{attempts}"
    target = bust_cache(url, salt)
    last_error = ""

    for attempt in range(1, attempts + 1):
        try:
            status, body, final_url = fetch(target, timeout)
        except urllib.error.HTTPError as exc:  # noqa: PERF203 - loop body
            last_error = f"HTTP {exc.code} {exc.reason}"
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            last_error = f"{type(exc).__name__}: {exc}"
        else:
            digest = hashlib.sha256(body).hexdigest()
            label = f"HTTP {status}  {len(body)} bytes  sha256 {digest}"
            if expected_sha256 is None:
                print(f"  ok    {url}\n        {label}")
                return True
            if digest == expected_sha256:
                note = "" if expected_size in (None, len(body)) else \
                    f"  (size differs: local {expected_size})"
                print(f"  ok    {url}\n        {label}  matches local{note}")
                return True
            last_error = (
                f"hash mismatch: served {digest}, local {expected_sha256} "
                f"({len(body)} served bytes"
                + (f", {expected_size} local bytes" if expected_size else "")
                + ")"
            )
            print(f"  ...   {url}\n        {label}  does not match local yet")

        if attempt < attempts:
            print(f"        attempt {attempt}/{attempts} failed ({last_error}); "
                  f"retrying in {delay}s (edge propagation)")
            time.sleep(delay)

    # stdout is block-buffered when it is not a terminal, so flush before
    # writing the failure to stderr or the two arrive out of order.
    sys.stdout.flush()
    print(f"  FAIL  {url}\n        {last_error}", file=sys.stderr)
    return False


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verify a published Pages deployment with a real HTTP read + hash.",
    )
    parser.add_argument("--url", action="append", required=True,
                        help="public URL to fetch; repeat for several")
    parser.add_argument("--file", action="append", default=[],
                        help="local file the URL should be byte-identical to; "
                             "repeat, paired with --url in order")
    parser.add_argument("--expect-sha256", action="append", default=[],
                        help="expected sha256 hex; repeat, paired with --url in order")
    parser.add_argument("--attempts", type=int, default=5,
                        help="fetch attempts per URL (default: 5)")
    parser.add_argument("--delay", type=int, default=10,
                        help="seconds between attempts (default: 10)")
    parser.add_argument("--timeout", type=int, default=30,
                        help="per-request timeout in seconds (default: 30)")
    args = parser.parse_args()

    urls = args.url
    if args.file and len(args.file) != len(urls):
        print("verify-publish: --file must be given once per --url", file=sys.stderr)
        return 2
    if args.expect_sha256 and len(args.expect_sha256) != len(urls):
        print("verify-publish: --expect-sha256 must be given once per --url", file=sys.stderr)
        return 2
    if not args.file and not args.expect_sha256:
        print("verify-publish: give --file or --expect-sha256 for every --url", file=sys.stderr)
        return 2

    print(f"verify-publish: {len(urls)} URL(s), {args.attempts} attempt(s) each, "
          f"{args.delay}s apart")
    print("-" * 70)

    failures = 0
    for index, url in enumerate(urls):
        expected_sha: str | None = None
        expected_size: int | None = None
        if args.file:
            local = Path(args.file[index])
            if not local.is_file():
                print(f"  FAIL  {url}\n        local file not found: {local}", file=sys.stderr)
                failures += 1
                continue
            expected_sha = local_sha256(local)
            expected_size = local.stat().st_size
        if args.expect_sha256:
            expected_sha = args.expect_sha256[index]
        if not verify_one(url, expected_sha, expected_size,
                          args.attempts, args.delay, args.timeout):
            failures += 1

    print("-" * 70)
    if failures:
        print(f"verify-publish: FAILED — {failures} of {len(urls)} URL(s) did not match")
        return 1
    print(f"verify-publish: all {len(urls)} URL(s) served the bytes that were deployed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
