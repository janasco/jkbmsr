#!/usr/bin/env python3
"""Validate the public OTA verification material this repository still publishes.

WHAT THIS SUPERSEDES
--------------------
This replaces ``validate_release_index.py``, which validated
``releases/firmware/releases.json`` — a firmware *mirror* index that was
deliberately stripped from the public repository on 2026-10-13 when firmware
delivery moved behind the account-gated API (``api.jkbmsr.com/v1/flash/*``).
That tree is correctly absent, so a check that required it was failing on input
the repository is right not to carry. The old check has been retired rather than
"satisfied" by restoring the stripped tree; see AGENTS.md (History, 2026-10-13)
and ``firmware/scripts/release.sh``'s ``write_public_ota_material`` for why there
is no published firmware index any more.

WHAT IT VALIDATES NOW
---------------------
Only what the public repository still publishes under ``releases/``:

  ota/<target>-latest.json         signed OTA metadata, one per OTA target
  ota/keys/public/<key id>.pem     the OTA public verification key(s)

For every metadata file it asserts that the fields are present and well formed,
that ``targetHardware`` matches the filename, that the named ``signingKeyId`` has
a published public key, and — the load-bearing part — that the ECDSA P-256
signature actually verifies against that published key over the exact payload
byte string ``release.sh`` signs:

    version \n targetHardware \n releasedAt \n sha256      (no trailing newline)

A metadata file that no client can verify against the key served beside it is a
broken release, and nothing in the old index check ever proved the signature.
"""

from __future__ import annotations

import base64
import json
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OTA_DIR = ROOT / "ota"
KEYS_DIR = OTA_DIR / "keys" / "public"

DOWNLOAD_URL = "/v1/ota/firmware"
SIGNATURE_ALGORITHM = "ecdsa-p256-sha256"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def fail(message: str) -> None:
    raise SystemExit(f"validate_ota_metadata: {message}")


def parse_ts(value: str) -> datetime:
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        fail(f"{path.name}: not valid JSON: {error}")


def require_str(meta: dict, field: str, path: Path) -> str:
    value = meta.get(field)
    if not isinstance(value, str) or not value:
        fail(f"{path.name}: field {field!r} is missing or empty")
    return value


def verify_signature(path: Path, meta: dict, key_path: Path) -> None:
    payload = "\n".join(
        [meta["version"], meta["targetHardware"], meta["releasedAt"], meta["sha256"]]
    )
    try:
        signature = base64.b64decode(meta["signature"], validate=True)
    except Exception as error:  # noqa: BLE001
        fail(f"{path.name}: signature is not valid base64: {error}")

    with tempfile.TemporaryDirectory() as tmp:
        payload_path = Path(tmp) / "payload"
        signature_path = Path(tmp) / "signature.bin"
        payload_path.write_bytes(payload.encode("utf-8"))
        signature_path.write_bytes(signature)
        result = subprocess.run(
            [
                "openssl",
                "dgst",
                "-sha256",
                "-verify",
                str(key_path),
                "-signature",
                str(signature_path),
                str(payload_path),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", "replace").strip()
        fail(
            f"{path.name}: signature does not verify against "
            f"{key_path.relative_to(ROOT)} ({detail})"
        )


def check_public_key(key_path: Path) -> None:
    text = key_path.read_text(encoding="utf-8")
    if "-----BEGIN PUBLIC KEY-----" not in text or "-----END PUBLIC KEY-----" not in text:
        fail(f"{key_path.relative_to(ROOT)}: not a PEM PUBLIC KEY block")
    result = subprocess.run(
        ["openssl", "pkey", "-pubin", "-in", str(key_path), "-text", "-noout"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        fail(f"{key_path.relative_to(ROOT)}: openssl could not parse it as a public key")
    if "256 bit" not in result.stdout.decode("utf-8", "replace"):
        fail(f"{key_path.relative_to(ROOT)}: not a P-256 (256-bit) key")


def main() -> None:
    if not OTA_DIR.is_dir():
        fail(f"no OTA directory at {OTA_DIR} — nothing to validate")

    metadata_files = sorted(OTA_DIR.glob("*-latest.json"))
    if not metadata_files:
        fail(f"no ota/<target>-latest.json files under {OTA_DIR}")

    if shutil.which("openssl") is None:
        fail("openssl is required to verify the published OTA signatures and is not on PATH")

    key_files = sorted(KEYS_DIR.glob("*.pem"))
    if not key_files:
        fail(f"no public OTA key(s) under {KEYS_DIR}")
    keys_by_id = {key.stem: key for key in key_files}
    for key_path in key_files:
        check_public_key(key_path)

    checked = 0
    for path in metadata_files:
        meta = load_json(path)

        target = require_str(meta, "targetHardware", path)
        if path.name != f"{target}-latest.json":
            fail(f"{path.name}: targetHardware {target!r} does not match the filename")
        require_str(meta, "version", path)
        released_at = require_str(meta, "releasedAt", path)
        try:
            parse_ts(released_at)
        except ValueError:
            fail(f"{path.name}: releasedAt {released_at!r} is not YYYY-MM-DDTHH:MM:SSZ")

        if meta.get("downloadUrl") != DOWNLOAD_URL:
            fail(f"{path.name}: downloadUrl must be {DOWNLOAD_URL!r}, got {meta.get('downloadUrl')!r}")
        if meta.get("signatureAlgorithm") != SIGNATURE_ALGORITHM:
            fail(
                f"{path.name}: signatureAlgorithm must be {SIGNATURE_ALGORITHM!r}, "
                f"got {meta.get('signatureAlgorithm')!r}"
            )

        sha256 = require_str(meta, "sha256", path)
        if not SHA256_RE.match(sha256):
            fail(f"{path.name}: sha256 {sha256!r} is not 64 lowercase hex characters")

        key_id = require_str(meta, "signingKeyId", path)
        key_path = keys_by_id.get(key_id)
        if key_path is None:
            fail(
                f"{path.name}: signingKeyId {key_id!r} has no published public key "
                f"(expected {KEYS_DIR.relative_to(ROOT)}/{key_id}.pem)"
            )

        # The signature is checked LAST so a malformed metadata file reports its
        # field problem before the crypto does.
        verify_signature(path, meta, key_path)
        checked += 1

    print(
        f"OTA metadata validation passed: {checked} target(s), "
        f"{len(key_files)} public key(s), all signatures verified"
    )


if __name__ == "__main__":
    main()
