#!/usr/bin/env python3
import base64
import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate generated OTA release artifacts before publish.")
    parser.add_argument("--release-dir", required=True, type=Path)
    parser.add_argument("--public-key", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--target-hardware", required=True)
    parser.add_argument("--released-at", required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--signing-key-id", required=True)
    parser.add_argument("--signature-algorithm", required=True)
    parser.add_argument("--download-url", default="/v1/ota/firmware")
    args = parser.parse_args()

    release_dir = args.release_dir.resolve()
    firmware_path = release_dir / "firmware.bin"
    checksum_path = release_dir / "firmware.sha256"
    metadata_path = release_dir / "firmware-metadata.json"
    public_key_path = args.public_key.resolve()

    for required_path in (firmware_path, checksum_path, metadata_path, public_key_path):
        if not required_path.exists():
            fail(f"Missing required file: {required_path}")

    actual_sha256 = sha256_file(firmware_path)
    if actual_sha256 != args.sha256:
        fail(f"Firmware SHA-256 mismatch: expected {args.sha256}, got {actual_sha256}")

    expected_checksum_line = f"{args.sha256}  jkbmsr-{args.target_hardware}-{args.version}.bin"
    checksum_lines = checksum_path.read_text(encoding="utf-8").strip().splitlines()
    if checksum_lines != [expected_checksum_line]:
        fail(f"Unexpected checksum file contents: {checksum_lines!r}")

    metadata = read_json(metadata_path)
    expected_metadata = {
        "version": args.version,
        "targetHardware": args.target_hardware,
        "releasedAt": args.released_at,
        "downloadUrl": args.download_url,
        "sha256": args.sha256,
        "signingKeyId": args.signing_key_id,
        "signatureAlgorithm": args.signature_algorithm,
    }

    for key, expected_value in expected_metadata.items():
        actual_value = metadata.get(key)
        if actual_value != expected_value:
            fail(f"Metadata field {key} mismatch: expected {expected_value!r}, got {actual_value!r}")

    signature = metadata.get("signature")
    if not isinstance(signature, str) or not signature:
        fail("Metadata signature is missing or empty")

    payload_path = release_dir / "signature-payload.txt"
    signature_path = release_dir / "signature.bin"
    payload_path.write_text(
        "\n".join([args.version, args.target_hardware, args.released_at, args.sha256]),
        encoding="utf-8",
    )
    try:
        signature_path.write_bytes(base64.b64decode(signature))
    except Exception as error:  # noqa: BLE001
        fail(f"Metadata signature is not valid base64: {error}")
    try:
        subprocess.run(
            [
                "openssl",
                "dgst",
                "-sha256",
                "-verify",
                str(public_key_path),
                "-signature",
                str(signature_path),
                str(payload_path),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError as error:
        fail(f"Signature verification failed: {error}")
    finally:
        payload_path.unlink(missing_ok=True)
        signature_path.unlink(missing_ok=True)

    print("OTA release bundle validation passed")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
