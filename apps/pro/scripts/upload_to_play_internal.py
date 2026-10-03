#!/usr/bin/env python3
"""Upload a signed .aab to a Google Play track via the Android Publisher API.

Deliberately self-contained: no `google-api-python-client` and no
`google-auth` are required, because the release host does not have them. Auth
is an RS256 JWT signed with `openssl`; the bundle is uploaded with an 8 MiB
chunked resumable upload (the API rejects a single-shot PUT of a 64 MB bundle
often enough to matter).

Usage:
  upload_to_play_internal.py \\
      --aab jkbmsr-pro-v1.3.37.aab \\
      --track internal --status completed \\
      --release-name 1.3.37 \\
      --release-notes-file whatsnew-en-US.txt

Auth (first found wins):
  --service-account PATH
  $GOOGLE_PLAY_SERVICE_ACCOUNT_JSON   (raw JSON content, not a path)

The service account and its Play Console scoping live only in the private
operations tree; nothing here is a secret.
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

PACKAGE_DEFAULT = "com.jkbmsr.pro"
CHUNK_SIZE = 8 * 1024 * 1024  # 8 MiB, and a multiple of the 256 KiB minimum.
API_ROOT = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"
UPLOAD_ROOT = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications"
TOKEN_SCOPE = "https://www.googleapis.com/auth/androidpublisher"


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """A resumable-upload chunk answers 308 Resume Incomplete; that is not an
    error and must not be followed as a redirect."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_OPENER = urllib.request.build_opener(_NoRedirect)


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _load_service_account(path: str | None) -> dict:
    if path:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    raw = os.environ.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")
    if not raw:
        raise SystemExit("provide --service-account PATH or GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")
    return json.loads(raw)


def access_token(sa: dict) -> str:
    now = int(time.time())
    header = _b64url(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    claims = _b64url(json.dumps({
        "iss": sa["client_email"],
        "scope": TOKEN_SCOPE,
        "aud": sa["token_uri"],
        "iat": now,
        "exp": now + 3600,
    }).encode())
    signing_input = f"{header}.{claims}".encode()

    # The private key is written to a 0600 temp file only for the duration of
    # the openssl call, then removed.
    fd, key_path = tempfile.mkstemp(suffix=".pem")
    try:
        os.write(fd, sa["private_key"].encode())
        os.close(fd)
        os.chmod(key_path, 0o600)
        signature = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", key_path, "-binary"],
            input=signing_input, capture_output=True, check=True,
        ).stdout
    finally:
        try:
            os.unlink(key_path)
        except OSError:
            pass

    assertion = f"{header}.{claims}.{_b64url(signature)}"
    body = urllib.parse.urlencode({
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion": assertion,
    }).encode()
    req = urllib.request.Request(sa["token_uri"], data=body, headers={
        "Content-Type": "application/x-www-form-urlencoded",
        "User-Agent": "jkbmsr-release/1.0",
    })
    with _OPENER.open(req, timeout=30) as resp:
        return json.load(resp)["access_token"]


def api(method: str, url: str, token: str, body: dict | None = None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "User-Agent": "jkbmsr-release/1.0",
    })
    try:
        with _OPENER.open(req, timeout=120) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as err:
        raw = err.read().decode(errors="replace")
        return err.code, raw


def open_edit(package: str, token: str) -> str:
    status, result = api("POST", f"{API_ROOT}/{package}/edits", token, body={})
    if status != 200:
        raise SystemExit(f"could not open a Play edit: {status} {result}")
    return result["id"]


def upload_bundle(package: str, edit_id: str, token: str, aab_path: str) -> int:
    total = os.path.getsize(aab_path)
    init_url = (
        f"{UPLOAD_ROOT}/{package}/edits/{edit_id}/bundles?uploadType=resumable"
    )
    req = urllib.request.Request(init_url, data=b"{}", method="POST", headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "X-Upload-Content-Type": "application/octet-stream",
        "X-Upload-Content-Length": str(total),
        "User-Agent": "jkbmsr-release/1.0",
    })
    try:
        with _OPENER.open(req, timeout=60) as resp:
            session_uri = resp.headers.get("Location")
    except urllib.error.HTTPError as err:
        raise SystemExit(f"could not start the upload session: {err.code} {err.read()!r}")
    if not session_uri:
        raise SystemExit("upload session response had no Location header")

    offset = 0
    with open(aab_path, "rb") as fh:
        while offset < total:
            chunk = fh.read(CHUNK_SIZE)
            end = offset + len(chunk) - 1
            status, body = _put_chunk(session_uri, chunk, offset, end, total)
            if status in (200, 201):
                return int(body["versionCode"])
            if status != 308:
                raise SystemExit(f"bundle upload failed: {status} {body!r}")
            offset = end + 1

        # A total that is an exact multiple of the chunk size needs one final
        # empty request to close the session.
        status, body = _put_chunk(session_uri, b"", None, None, total)
        if status in (200, 201):
            return int(body["versionCode"])
        raise SystemExit(f"bundle upload finalisation failed: {status} {body!r}")


def _put_chunk(session_uri, chunk, start, end, total):
    if start is None:
        content_range = f"bytes */{total}"
    else:
        content_range = f"bytes {start}-{end}/{total}"
    req = urllib.request.Request(session_uri, data=chunk, method="PUT", headers={
        "Content-Type": "application/octet-stream",
        "Content-Length": str(len(chunk)),
        "Content-Range": content_range,
        "User-Agent": "jkbmsr-release/1.0",
    })
    try:
        with _OPENER.open(req, timeout=600) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as err:
        raw = err.read().decode(errors="replace")
        # A 308 is the normal "keep going" answer and arrives via HTTPError.
        if err.code == 308:
            return 308, raw
        return err.code, raw


def set_track(package, edit_id, token, track, version_code, name, notes):
    release = {"versionCodes": [str(version_code)], "status": "completed"}
    if name:
        release["name"] = name
    if notes:
        release["releaseNotes"] = [{"language": "en-US", "text": notes}]
    status, result = api(
        "PUT", f"{API_ROOT}/{package}/edits/{edit_id}/tracks/{track}", token,
        body={"track": track, "releases": [release]},
    )
    if status != 200:
        raise SystemExit(f"could not attach versionCode {version_code} to '{track}': {status} {result}")
    return result


def commit_edit(package, edit_id, token):
    """Commit, adapting to the app's publishing mode.

    Apps with managed publishing enabled require
    `changesNotSentForReview=true`; apps without it reject that parameter's
    absence or presence depending on mode. Try the plain commit first and
    retry with the flag only when the API says it needs it, so this cannot
    silently send a release for review that the owner wanted held.
    """
    status, result = api("POST", f"{API_ROOT}/{package}/edits/{edit_id}:commit", token, body={})
    if status == 200:
        return "plain", result
    text = result if isinstance(result, str) else json.dumps(result)
    if "changesNotSentForReview" in text or "sent for review" in text.lower():
        status, result = api(
            "POST",
            f"{API_ROOT}/{package}/edits/{edit_id}:commit?changesNotSentForReview=true",
            token, body={},
        )
        if status == 200:
            return "changesNotSentForReview=true", result
    raise SystemExit(f"commit failed: {status} {text}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-name", default=PACKAGE_DEFAULT)
    parser.add_argument("--aab", required=True)
    parser.add_argument("--track", default="internal",
                        choices=["internal", "alpha", "beta", "production"])
    parser.add_argument("--release-name", default="")
    parser.add_argument("--release-notes-file")
    parser.add_argument("--service-account")
    args = parser.parse_args()

    if not os.path.isfile(args.aab):
        raise SystemExit(f"no such .aab: {args.aab}")

    notes = None
    if args.release_notes_file:
        with open(args.release_notes_file, encoding="utf-8") as fh:
            notes = fh.read().strip() or None

    sa = _load_service_account(args.service_account)
    token = access_token(sa)
    print(f"Authenticated as {sa['client_email']}")

    edit_id = open_edit(args.package_name, token)
    print(f"Opened edit {edit_id}")

    version_code = upload_bundle(args.package_name, edit_id, token, args.aab)
    print(f"Uploaded bundle, versionCode={version_code}")

    set_track(args.package_name, edit_id, token, args.track, version_code,
              args.release_name, notes)
    print(f"Attached versionCode {version_code} to '{args.track}'")

    flavour, _ = commit_edit(args.package_name, edit_id, token)
    print(f"Edit committed ({flavour}).")
    print(f"RESULT versionCode={version_code} track={args.track}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
