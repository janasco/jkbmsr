#!/usr/bin/env python3
"""Uploads a signed .aab to Google Play Console via the Android Publisher API.

Usage:
  upload_to_play_console.py --package-name com.jkbmsr.pro \
      --aab path/to/app.aab --track production --status draft \
      --release-notes-file whatsnew-en-US.txt

Auth: reads the service account JSON from the GOOGLE_PLAY_SERVICE_ACCOUNT_JSON
env var (raw JSON content, not a path) — supplied from the release machine's
local environment, never
written to disk. See the signing policy in the private operations repository for how this service
account is scoped (Play Console API access, release-management permission
for this app only — deliberately NOT a GCP project role; see that doc for
why that distinction matters).

status=draft uploads the release and attaches it to the track, but leaves
it unpublished — a human still has to click "Start rollout" in Play
Console. Deliberate default: this is unattended CI, and a pipeline bug
should never be able to auto-publish to real users. Use --status completed
only once this pipeline has proven itself reliable.

Exits non-zero (failing the release build) on any API error — a failed
Play Console upload should be loud, not a silently-skipped step.
"""
import argparse
import json
import os
import sys

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

SCOPES = ["https://www.googleapis.com/auth/androidpublisher"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-name", required=True)
    parser.add_argument("--aab", required=True, help="Path to the signed .aab file")
    parser.add_argument("--track", default="production", choices=["internal", "alpha", "beta", "production"])
    parser.add_argument("--status", default="draft", choices=["draft", "inProgress", "completed"])
    parser.add_argument("--release-notes-file", help="Plain-text release notes (en-US), optional")
    args = parser.parse_args()

    raw_key = os.environ.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")
    if not raw_key:
        print("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is not set", file=sys.stderr)
        return 1
    if not os.path.isfile(args.aab):
        print(f"No such file: {args.aab}", file=sys.stderr)
        return 1

    release_notes = None
    if args.release_notes_file:
        with open(args.release_notes_file, encoding="utf-8") as f:
            text = f.read().strip()
        if text:
            release_notes = [{"language": "en-US", "text": text}]

    credentials = service_account.Credentials.from_service_account_info(json.loads(raw_key), scopes=SCOPES)
    service = build("androidpublisher", "v3", credentials=credentials)
    edits = service.edits()

    edit_id = edits.insert(body={}, packageName=args.package_name).execute()["id"]
    print(f"Opened edit {edit_id} for {args.package_name}")

    try:
        bundle = edits.bundles().upload(
            editId=edit_id,
            packageName=args.package_name,
            media_body=MediaFileUpload(args.aab, mimetype="application/octet-stream"),
        ).execute()
        version_code = bundle["versionCode"]
        print(f"Uploaded bundle, versionCode={version_code}")

        release = {"versionCodes": [str(version_code)], "status": args.status}
        if release_notes:
            release["releaseNotes"] = release_notes

        edits.tracks().update(
            editId=edit_id,
            packageName=args.package_name,
            track=args.track,
            body={"releases": [release]},
        ).execute()
        print(f"Attached versionCode {version_code} to track '{args.track}' with status '{args.status}'")

        edits.commit(editId=edit_id, packageName=args.package_name).execute()
        print("Edit committed.")
    except Exception:
        # An uncommitted edit just expires on its own after ~a few hours —
        # no explicit rollback call needed, and validate() would only catch
        # what commit() already surfaces.
        print("Upload failed; the edit was left uncommitted and will expire unpublished.", file=sys.stderr)
        raise

    if args.status == "draft":
        print(f"Draft release created for '{args.track}' — review and start the rollout manually in Play Console.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
