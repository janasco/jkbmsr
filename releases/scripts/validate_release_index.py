#!/usr/bin/env python3
import json
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FIRMWARE_DIR = ROOT / "firmware"
INDEX_PATH = FIRMWARE_DIR / "releases.json"


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def parse_ts(value: str) -> datetime:
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")


def ensure(condition: bool, message: str):
    if not condition:
        raise SystemExit(message)


def main():
    index = load_json(INDEX_PATH)

    ensure(index.get("publicBaseUrl") == "https://cdn.jkbmsr.com", "releases.json must declare https://cdn.jkbmsr.com as publicBaseUrl")
    ensure(isinstance(index.get("releases"), list) and index["releases"], "releases.json must contain at least one release entry")

    releases = index["releases"]
    sorted_releases = sorted(releases, key=lambda item: parse_ts(item["releasedAt"]), reverse=True)
    ensure(releases == sorted_releases, "releases.json must be sorted by releasedAt descending")

    # One release entry per (targetHardware, version) pair, and — since
    # firmware/<target>/latest.json replaced the old single global
    # firmware/latest.json — exactly one isLatest=true release PER target
    # hardware model, not one globally across the whole catalog. A release
    # for ESP8266 must not hide the latest ESP32 build (or vice versa).
    releases_by_target: dict[str, list] = {}
    for release in releases:
        releases_by_target.setdefault(release["targetHardware"], []).append(release)

    for target, target_releases in releases_by_target.items():
        latest_json_path = FIRMWARE_DIR / target / "latest.json"
        ensure(latest_json_path.exists(), f"missing firmware/{target}/latest.json")
        latest = load_json(latest_json_path)
        ensure(latest["targetHardware"] == target, f"firmware/{target}/latest.json targetHardware mismatch")

        latest_matches = [release for release in target_releases if release["version"] == latest["currentVersion"]]
        ensure(len(latest_matches) == 1, f"firmware/{target}/latest.json must point to exactly one release entry in releases.json")
        latest_entry = latest_matches[0]
        ensure(latest_entry.get("isLatest") is True, f"latest release entry for {target} must be marked isLatest=true")
        ensure(latest_entry["releasedAt"] == latest["releasedAt"], f"latest release timestamp must match releases.json for {target}")

        latest_count = sum(1 for release in target_releases if release.get("isLatest"))
        ensure(latest_count == 1, f"releases.json must contain exactly one isLatest=true entry for {target}")

    for release in releases:
      manifest_rel = release["artifacts"]["manifest"]
      manifest_path = FIRMWARE_DIR / manifest_rel.removeprefix("./")
      ensure(manifest_path.exists(), f"missing manifest file: {manifest_rel}")
      manifest = load_json(manifest_path)

      ensure(manifest["version"] == release["version"], f"manifest version mismatch for {manifest_rel}")
      ensure(manifest["targetHardware"] == release["targetHardware"], f"manifest target mismatch for {manifest_rel}")
      ensure(manifest["releasedAt"] == release["releasedAt"], f"manifest release date mismatch for {manifest_rel}")

      for artifact_name, artifact_rel in release["artifacts"].items():
          # Non-OTA targets (no OTA subsystem at all — USB reflash only, see
          # jkbmsr-firmware's docs/esp8266-nodemcu-support.md) publish no
          # firmware-metadata.json, so this field is legitimately null there.
          if artifact_rel is None:
              continue
          artifact_path = FIRMWARE_DIR / artifact_rel.removeprefix("./")
          ensure(artifact_path.exists(), f"missing artifact {artifact_name}: {artifact_rel}")

    print("Release index validation passed")


if __name__ == "__main__":
    main()
