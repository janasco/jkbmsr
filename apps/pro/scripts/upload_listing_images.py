#!/usr/bin/env python3
"""Replace a Play listing's images from a directory, in filename order.

The Contributor listing's images were uploaded by hand, which is how a set
generated before the icon font was loaded stayed live for weeks: nothing compared
the store against the folder. This deletes the current set and uploads the files
in sorted order, so the listing's order IS the filenames' order — which is why the
generator numbers its shots — and the result can be read back.

Usage:
  python3 upload_listing_images.py \\
      --package-name com.jkbmsr.contributor \\
      --dir ../../contributor/build/store-screenshots \\
      --image-type phoneScreenshots [--language en-US] [--dry-run]

  --dry-run uploads the whole set into a throwaway edit and deletes it: the upload
  path is exercised end to end and nothing is attached to the listing.

Auth: --service-account PATH, or $GOOGLE_PLAY_SERVICE_ACCOUNT_JSON (raw JSON).
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import play_api  # noqa: E402


def list_images(package, edit, token, language, image_type):
    status, body = play_api.api(
        "GET",
        f"{play_api.API_ROOT}/{package}/edits/{edit}/listings/{language}/{image_type}",
        token,
    )
    if status != 200:
        raise play_api.PlayApiError(f"could not list {image_type}: {status} {body}")
    return body.get("images", [])


def delete_image(package, edit, token, language, image_type, image_id):
    status, body = play_api.api(
        "DELETE",
        f"{play_api.API_ROOT}/{package}/edits/{edit}/listings/{language}/{image_type}/{image_id}",
        token,
    )
    if status not in (200, 204):
        raise play_api.PlayApiError(f"could not delete {image_id}: {status} {body}")


def upload_image(package, edit, token, language, image_type, path):
    # The media upload host carries the `/upload/` prefix; without it the PNG is
    # parsed as JSON and rejected with an unhelpful message.
    url = (
        f"{play_api.UPLOAD_ROOT}/{package}/edits/{edit}/listings/"
        f"{language}/{image_type}?uploadType=media"
    )
    with open(path, "rb") as handle:
        data = handle.read()
    request = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "image/png",
            "Content-Length": str(len(data)),
            "User-Agent": play_api.USER_AGENT,
        },
    )
    try:
        with play_api._OPENER.open(request, timeout=600) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as err:
        raise play_api.PlayApiError(
            f"could not upload {os.path.basename(path)}: {err.code} {err.read()!r}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Replace a Play listing's images from a directory, in filename order.",
    )
    parser.add_argument("--package-name", required=True)
    parser.add_argument("--dir", required=True, help="folder of .png files")
    parser.add_argument("--image-type", default="phoneScreenshots")
    parser.add_argument("--language", default="en-US")
    parser.add_argument("--service-account")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    files = sorted(
        os.path.join(args.dir, name)
        for name in os.listdir(args.dir)
        if name.lower().endswith(".png")
    )
    if not files:
        print(f"no .png files in {args.dir}", file=sys.stderr)
        return 2

    service_account = play_api.load_service_account(args.service_account)
    token = play_api.access_token(service_account)
    print(f"Authenticated as {service_account.get('client_email', '?')}")

    edit = play_api.open_edit(args.package_name, token)
    try:
        existing = list_images(
            args.package_name, edit, token, args.language, args.image_type
        )
        print(
            f"Replacing {len(existing)} existing {args.image_type} "
            f"with {len(files)} from {args.dir}"
        )
        if not args.dry_run:
            for image in existing:
                # The API calls it `id`; older docs call it `imageId`.
                image_id = image.get("id") or image.get("imageId")
                if not image_id:
                    raise play_api.PlayApiError(f"listing image without an id: {image}")
                delete_image(
                    args.package_name, edit, token, args.language, args.image_type,
                    image_id,
                )

        for index, path in enumerate(files, start=1):
            image = upload_image(
                args.package_name, edit, token, args.language, args.image_type, path
            )
            print(
                f"  {index}/{len(files)}  {os.path.basename(path)} "
                f"-> {image.get('imageId', '?')}"
            )

        if args.dry_run:
            print("Dry run: uploaded into a throwaway edit; nothing attached or committed.")
            return 0

        mode, result = play_api.commit_edit(args.package_name, edit, token)
        print(f"Edit committed ({mode}).")
        return 0
    finally:
        if args.dry_run:
            try:
                play_api.delete_edit(args.package_name, edit, token)
            except Exception as err:  # noqa: BLE001 - the edit expires on its own
                print(f"  could not delete the dry-run edit: {err}", file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main())
