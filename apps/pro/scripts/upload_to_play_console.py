#!/usr/bin/env python3
"""Uploads a signed .aab to Google Play Console via the Android Publisher API.

Usage:
  upload_to_play_console.py --package-name com.jkbmsr.pro \
      --aab path/to/app.aab --track production --status draft \
      --release-notes-file whatsnew-en-US.txt

  upload_to_play_console.py --package-name com.jkbmsr.pro \
      --aab path/to/app.aab --dry-run        # exercises the upload, publishes nothing

Auth (first found wins):
  --service-account PATH
  $GOOGLE_PLAY_SERVICE_ACCOUNT_JSON   (raw JSON content, not a path)

The service account and its Play Console scoping live only in the private
operations tree; nothing here is a secret. There is no `google-api-python-client`
and no `google-auth` dependency — see play_api.py, which owns the chunked
resumable upload and why it is chunked.

status=draft uploads the release and attaches it to the track, but leaves it
unpublished — a human still has to click "Start rollout" in Play Console.
Deliberate default: a pipeline bug should never be able to auto-publish to real
users. Use --status completed only deliberately.

--dry-run uploads the bundle into a throwaway edit and then deletes that edit,
attaching it to no track and committing nothing. It exercises the whole upload
path and publishes nothing, which is the only way to verify this script without
shipping a version.

Exits non-zero (failing the release build) on any API error — a failed Play
Console upload should be loud, not a silently-skipped step.
"""
import argparse
import os
import sys

import play_api


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-name", required=True)
    parser.add_argument("--aab", required=True, help="Path to the signed .aab file")
    parser.add_argument("--track", default="production",
                        choices=["internal", "alpha", "beta", "production"])
    parser.add_argument("--status", default="draft",
                        choices=["draft", "inProgress", "completed"])
    parser.add_argument("--release-name", default="")
    parser.add_argument("--release-notes-file", help="Plain-text release notes (en-US), optional")
    parser.add_argument("--service-account", help="Path to the service account JSON")
    parser.add_argument("--dry-run", action="store_true",
                        help="Upload into a throwaway edit and delete it; attach nothing, commit nothing")
    args = parser.parse_args()

    if not os.path.isfile(args.aab):
        print(f"No such file: {args.aab}", file=sys.stderr)
        return 1

    notes = None
    if args.release_notes_file:
        with open(args.release_notes_file, encoding="utf-8") as fh:
            notes = fh.read().strip() or None

    try:
        sa = play_api.load_service_account(args.service_account)
        token = play_api.access_token(sa)
    except play_api.PlayApiError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print(f"Authenticated as {sa['client_email']}")

    edit_id = play_api.open_edit(args.package_name, token)
    print(f"Opened edit {edit_id} for {args.package_name}")

    try:
        version_code = play_api.upload_bundle(args.package_name, edit_id, token, args.aab)
        print(f"Uploaded bundle, versionCode={version_code}")

        if args.dry_run:
            play_api.delete_edit(args.package_name, edit_id, token)
            print("Dry run: the bundle uploaded and the edit was deleted. "
                  "Nothing was attached or committed.")
            return 0

        play_api.set_track(args.package_name, edit_id, token, args.track,
                           version_code, args.status, args.release_name, notes)
        print(f"Attached versionCode {version_code} to track '{args.track}' "
              f"with status '{args.status}'")

        flavour, _ = play_api.commit_edit(args.package_name, edit_id, token)
        print(f"Edit committed ({flavour}).")
    except play_api.PlayApiError as exc:
        # An uncommitted edit just expires on its own after ~a few hours — no
        # explicit rollback call needed. Loud, but without a traceback: this is
        # an expected API answer, not a bug in here.
        print(f"Upload failed: {exc}", file=sys.stderr)
        print("The edit was left uncommitted and will expire unpublished.", file=sys.stderr)
        return 1
    except Exception:
        print("Upload failed unexpectedly; the edit was left uncommitted and will "
              "expire unpublished.", file=sys.stderr)
        raise

    if args.status == "draft":
        print(f"Draft release created for '{args.track}' — review and start the "
              "rollout manually in Play Console.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
