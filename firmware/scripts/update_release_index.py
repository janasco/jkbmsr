#!/usr/bin/env python3
"""Update the public release index (firmware/releases.json) for a new release.

Run from the root of a checked-out jkbmsr-releases working tree. Reads all
inputs from environment variables so it can be invoked cleanly from CI without
fragile inline heredocs (this logic previously lived as an inline
`python3 - <<'PY'` block inside the release workflow, where mismatched
indentation made the workflow YAML itself unparseable).

Required environment variables:
  RELEASE_VERSION, RELEASE_TARGET_HARDWARE, RELEASE_RELEASED_AT,
  RELEASE_TAG, RELEASE_SHA256, RELEASE_HAS_OTA
  RELEASE_SIGNATURE, RELEASE_SIGNING_KEY_ID, RELEASE_SIGNATURE_ALGORITHM are
  required only when RELEASE_HAS_OTA=true — a non-OTA target (currently just
  ESP8266 — USB reflash only, see docs/esp8266-nodemcu-support.md) publishes
  neither a firmware-metadata.json nor OTA signing metadata at all, so both
  the "metadata" artifact and "otaMetadata" become null instead of a
  placeholder value, matching what generate-flash-manifest.py's caller
  (ota-release.yml) writes into that target's own release.json.
"""
import json
import os
import sys
from pathlib import Path

PUBLIC_BASE_URL = "https://cdn.jkbmsr.com"


def env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        sys.exit(f"update_release_index: required environment variable {name} is empty")
    return value


def main() -> None:
    version = env("RELEASE_VERSION")
    target_hardware = env("RELEASE_TARGET_HARDWARE")
    released_at = env("RELEASE_RELEASED_AT")
    release_tag = env("RELEASE_TAG")
    sha256 = env("RELEASE_SHA256")
    has_ota = env("RELEASE_HAS_OTA") == "true"

    index_path = Path("firmware/releases.json")
    if index_path.exists():
        data = json.loads(index_path.read_text(encoding="utf-8"))
    else:
        data = {"publicBaseUrl": PUBLIC_BASE_URL, "releases": []}

    version_dir = f"./{target_hardware}/v{version}"

    if has_ota:
        signature = env("RELEASE_SIGNATURE")
        key_id = env("RELEASE_SIGNING_KEY_ID")
        algorithm = env("RELEASE_SIGNATURE_ALGORITHM")
        metadata_artifact = f"{version_dir}/firmware-metadata.json"
        ota_metadata = {
            "version": version,
            "targetHardware": target_hardware,
            "releasedAt": released_at,
            "downloadUrl": "/v1/ota/firmware",
            "sha256": sha256,
            "signature": signature,
            "signingKeyId": key_id,
            "signatureAlgorithm": algorithm,
        }
    else:
        metadata_artifact = None
        ota_metadata = None

    # Drop any existing entry for this exact version+target so re-runs are
    # idempotent, then add the fresh one.
    releases = [
        item
        for item in data.get("releases", [])
        if not (item.get("version") == version and item.get("targetHardware") == target_hardware)
    ]
    releases.append(
        {
            "version": version,
            "targetHardware": target_hardware,
            "releasedAt": released_at,
            "githubReleaseTag": release_tag,
            "isLatest": True,
            "artifacts": {
                "firmware": f"{version_dir}/firmware.bin",
                "checksum": f"{version_dir}/firmware.sha256",
                "metadata": metadata_artifact,
                "releaseNotes": f"{version_dir}/RELEASE_NOTES.md",
                "manifest": f"{version_dir}/release.json",
                "flashManifest": f"{version_dir}/flash-manifest.json",
            },
            "otaMetadata": ota_metadata,
        }
    )

    # Newest first, and exactly one latest entry *per target*. A release for
    # ESP8266 must not hide the latest ESP32 build (or vice versa).
    releases.sort(key=lambda item: item.get("releasedAt", ""), reverse=True)
    latest_seen: set[str] = set()
    for item in releases:
        item_target = item.get("targetHardware", "")
        item["isLatest"] = item_target not in latest_seen
        latest_seen.add(item_target)

    data["publicBaseUrl"] = PUBLIC_BASE_URL
    data["releases"] = releases
    index_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"update_release_index: wrote {len(releases)} release entries, latest = {version} ({target_hardware})")


if __name__ == "__main__":
    main()
