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
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

USER_AGENT = "jkbmsr-verify-publish/1.0"

# Cloudflare injects elements into responses it serves from its own zone. On a
# zone with Web Analytics enabled that includes a 367-byte
# static.cloudflareinsights.com/beacon.min.js <script>, added to the *served*
# bytes and not present in the build output. Hashing the served body against the
# local file therefore reports a mismatch for a deploy that is byte-for-byte
# correct -- which is what happened on 2026-09-28, on a deploy that had in fact
# landed. A verifier that cries wolf on every correct publish is a verifier whose
# verdict nobody reads, so the difference is normalised away -- and REPORTED, never
# swallowed. If a normalisation is what made the comparison pass, the run says so
# and names what was removed.
#
# The list is deliberately narrow and named. A pattern that silently deletes
# anything it did not expect is a way to make a wrong deploy look right.
EDGE_INJECTED = (
    # The trailing `\s*` is load-bearing, and was found by MEASUREMENT rather than
    # by reasoning. Cloudflare injects the beacon as `\n<script ...></script>` just
    # before `</body>`, so removing only the element leaves an orphan newline and
    # the comparison still fails. Measured against the live docs site: element only
    # -> 28748 B, + LEADING whitespace -> 28740 B, + TRAILING whitespace -> 28747 B,
    # which equals the local build exactly. Consuming the leading whitespace
    # instead is wrong, and over-removes 8 bytes of real content.
    ("cloudflare web analytics beacon",
     re.compile(rb"<script[^>]*cloudflareinsights[^>]*>\s*</script>\s*", re.S)),
    ("cloudflare web analytics beacon (self-closing form)",
     re.compile(rb"<script[^>]*cloudflareinsights[^>]*/>\s*", re.S)),
)


def normalise(body: bytes) -> tuple[bytes, list[str]]:
    """Strip known edge-injected elements, reporting each removal.

    Returns the normalised bytes and a human-readable list of what was removed,
    so the caller can never present a normalised match as a byte-exact one.
    """
    removed: list[str] = []
    out = body
    for name, pattern in EDGE_INJECTED:
        stripped, count = pattern.subn(b"", out)
        if count:
            removed.append(f"{name} x{count} ({len(out) - len(stripped)} bytes)")
            out = stripped
    # NO trailing-whitespace normalisation. There was one, and it was a defect.
    #
    # It was added as a "safety net" and never once fired on the case it was
    # written for -- the beacon pattern's trailing `\s*` already removes the
    # whitespace the injection brings, and with it the served body is byte-equal
    # to local. What it DID do was create a path where a deploy that genuinely
    # differs passes: a served body with three extra trailing bytes, and nothing
    # establishing that the EDGE added them rather than the deploy, was reported
    #
    #     ok  … matches local AFTER removing
    #           - trailing whitespace (3 bytes)
    #       (the edge added this; the published build is byte-exact)
    #
    # which is false on both counts -- they are not equal, and the attribution was
    # invented. This tool verifies firmware on cdn.jkbmsr.com, so a wrong artifact
    # reported as byte-exact is the worst thing it could do.
    #
    # The rule this encodes: every normalisation must name WHAT it removes and be
    # attributable to the edge. A difference we cannot attribute is a difference
    # we must report.
    return out, removed


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
            # The raw bytes differ. Before calling that a failed deploy, ask
            # whether the only difference is something the edge added on its way
            # past us. If so this IS a successful deploy and reporting it as a
            # mismatch is the false alarm this whole path exists to remove.
            stripped, removed = normalise(body)
            if removed:
                normalised = hashlib.sha256(stripped).hexdigest()
                if normalised == expected_sha256:
                    print(f"  ok    {url}\n        {label}  matches local AFTER removing")
                    for item in removed:
                        print(f"              - {item}")
                    print("        (the edge added exactly this and nothing else; the published")
                    print("         build is byte-equal to local once it is removed)")
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
