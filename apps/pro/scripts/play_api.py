#!/usr/bin/env python3
"""Android Publisher API primitives shared by the Play upload scripts.

Deliberately self-contained: no `google-api-python-client` and no `google-auth`.
Auth is an RS256 JWT signed with `openssl`, and the bundle goes up as a
**chunked resumable upload**.

WHY THE UPLOAD IS CHUNKED AND RESUMPTABLE
  A Play bundle is tens of megabytes, and a single-shot write of one stalls on
  this host's link often enough to matter. Measured 2026-10-16 during the BLE
  4.17.29 release: four consecutive `TimeoutError: The write operation timed
  out` at 61.8 MB — a size that had uploaded fine hours earlier, so the link and
  not the build. `googleapiclient`'s `bundles().upload()` writes the whole body
  in one blocking request through httplib2, so one stalled send loses the entire
  attempt. A resumable session sends 8 MiB chunks and resumes from the last
  offset the server acknowledged, so a stall costs one chunk rather than the
  release. This was first written for `upload_to_play_internal.py` on 2026-10-03;
  it is here now so there is exactly one implementation.

  The upload host needs Google's `/upload/` prefix
  (`.../upload/androidpublisher/v3/...`). Without it the bundle is parsed as
  JSON and rejected with `Unexpected token PK`.

Nothing here is a secret; the service account and its Play Console scoping live
only in the private operations tree.
"""
import base64
import json
import os
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

# 8 MiB, and a multiple of the 256 KiB minimum the resumable protocol requires.
CHUNK_SIZE = 8 * 1024 * 1024
API_ROOT = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"
UPLOAD_ROOT = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications"
TOKEN_SCOPE = "https://www.googleapis.com/auth/androidpublisher"
USER_AGENT = "jkbmsr-release/1.0"


class PlayApiError(RuntimeError):
    """An Android Publisher API call failed.

    Raised rather than SystemExit so a caller owns the message: the CLI can say
    what it left behind, and a library caller can decide for itself.
    """


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """A resumable-upload chunk answers 308 Resume Incomplete; that is not an
    error and must not be followed as a redirect."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_OPENER = urllib.request.build_opener(_NoRedirect)


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def load_service_account(path: str | None = None) -> dict:
    """Read the service account JSON from a path, else the env var."""
    if path:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    raw = os.environ.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")
    if not raw:
        raise PlayApiError(
            "provide --service-account PATH or GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")
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
        "User-Agent": USER_AGENT,
    })
    with _OPENER.open(req, timeout=30) as resp:
        return json.load(resp)["access_token"]


def api(method: str, url: str, token: str, body: dict | None = None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "User-Agent": USER_AGENT,
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
        raise PlayApiError(f"could not open a Play edit: {status} {result}")
    return result["id"]


def delete_edit(package: str, edit_id: str, token: str) -> None:
    """Discard an edit without committing it. Used by --dry-run."""
    status, result = api("DELETE", f"{API_ROOT}/{package}/edits/{edit_id}", token)
    if status not in (200, 204):
        raise PlayApiError(f"could not delete the edit: {status} {result}")


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
        "User-Agent": USER_AGENT,
    })
    try:
        with _OPENER.open(req, timeout=60) as resp:
            session_uri = resp.headers.get("Location")
    except urllib.error.HTTPError as err:
        raise PlayApiError(f"could not start the upload session: {err.code} {err.read()!r}")
    if not session_uri:
        raise PlayApiError("upload session response had no Location header")

    offset = 0
    with open(aab_path, "rb") as fh:
        while offset < total:
            chunk = fh.read(CHUNK_SIZE)
            end = offset + len(chunk) - 1
            status, body = _put_chunk(session_uri, chunk, offset, end, total)
            if status in (200, 201):
                return int(body["versionCode"])
            if status != 308:
                raise PlayApiError(f"bundle upload failed: {status} {body!r}")
            offset = end + 1

        # A total that is an exact multiple of the chunk size needs one final
        # empty request to close the session.
        status, body = _put_chunk(session_uri, b"", None, None, total)
        if status in (200, 201):
            return int(body["versionCode"])
        raise PlayApiError(f"bundle upload finalisation failed: {status} {body!r}")


def _put_chunk(session_uri, chunk, start, end, total):
    if start is None:
        content_range = f"bytes */{total}"
    else:
        content_range = f"bytes {start}-{end}/{total}"
    req = urllib.request.Request(session_uri, data=chunk, method="PUT", headers={
        "Content-Type": "application/octet-stream",
        "Content-Length": str(len(chunk)),
        "Content-Range": content_range,
        "User-Agent": USER_AGENT,
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


def set_track(package, edit_id, token, track, version_code, status,
              name=None, notes=None):
    release = {"versionCodes": [str(version_code)], "status": status}
    if name:
        release["name"] = name
    if notes:
        release["releaseNotes"] = [{"language": "en-US", "text": notes}]
    status_code, result = api(
        "PUT", f"{API_ROOT}/{package}/edits/{edit_id}/tracks/{track}", token,
        body={"track": track, "releases": [release]},
    )
    if status_code != 200:
        raise PlayApiError(
            f"could not attach versionCode {version_code} to '{track}': {status_code} {result}")
    return result


def commit_edit(package: str, edit_id: str, token: str):
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
