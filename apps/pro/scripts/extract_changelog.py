#!/usr/bin/env python3
"""Extract one release's notes from CHANGELOG.md for release.yml.

Usage: extract_changelog.py <version> <output_file>
  version:     the tag being released, e.g. "v1.2.14" (must match a
               "## v1.2.14" heading in CHANGELOG.md exactly)
  output_file: where to write the plain-text bullet list, ready to paste
               into Google Play Console's "What's new in this version"
               field (hard 500-character limit per release, enforced here
               too — fails loudly instead of silently truncating, since a
               cut-off sentence is worse than a build failure asking you
               to shorten it).

Exits non-zero (failing the release build) if the version has no
CHANGELOG.md entry at all, or if the entry is too long for Play Store.
"""
import re
import sys

PLAY_STORE_WHATSNEW_LIMIT = 500


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: extract_changelog.py <version> <output_file>", file=sys.stderr)
        return 2
    version, output_file = sys.argv[1], sys.argv[2]

    with open("CHANGELOG.md", encoding="utf-8") as f:
        content = f.read()

    pattern = re.compile(
        rf"^## {re.escape(version)}\s*\n(.*?)(?=\n## |\Z)", re.MULTILINE | re.DOTALL
    )
    match = pattern.search(content)
    if not match:
        print(
            f"No CHANGELOG.md entry found for {version}. "
            f"Add a \"## {version}\" section describing what changed before releasing.",
            file=sys.stderr,
        )
        return 1

    bullets = [line.strip() for line in match.group(1).strip().splitlines() if line.strip().startswith("-")]
    if not bullets:
        print(f"CHANGELOG.md's \"## {version}\" section has no bullet points.", file=sys.stderr)
        return 1

    whatsnew = "\n".join(bullets)
    if len(whatsnew) > PLAY_STORE_WHATSNEW_LIMIT:
        print(
            f"CHANGELOG.md entry for {version} is {len(whatsnew)} characters — "
            f"Google Play's \"What's new\" limit is {PLAY_STORE_WHATSNEW_LIMIT}. Shorten it.",
            file=sys.stderr,
        )
        return 1

    with open(output_file, "w", encoding="utf-8") as f:
        f.write(whatsnew + "\n")

    print(whatsnew)
    return 0


if __name__ == "__main__":
    sys.exit(main())
