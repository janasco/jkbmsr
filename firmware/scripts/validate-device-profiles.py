#!/usr/bin/env python3
"""Validate supported-device profiles using only the Python standard library."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEVICES = ROOT / "devices"
REQUIRED = {"id", "manufacturer", "model", "hardware_revisions", "protocol", "transport", "implementation", "status"}


def main() -> None:
    profiles = sorted(DEVICES.glob("*/profile.json"))
    if not profiles:
        raise SystemExit("No device profiles found")

    seen_ids: set[str] = set()
    for path in profiles:
        profile = json.loads(path.read_text(encoding="utf-8"))
        missing = REQUIRED - profile.keys()
        if missing:
            raise SystemExit(f"{path}: missing fields: {', '.join(sorted(missing))}")

        profile_id = profile["id"]
        if profile_id != path.parent.name:
            raise SystemExit(f"{path}: id must match directory name")
        if profile_id in seen_ids:
            raise SystemExit(f"{path}: duplicate id {profile_id}")
        seen_ids.add(profile_id)

        for target in profile["implementation"].values():
            targets = target if isinstance(target, list) else [target]
            for relative in targets:
                if not (ROOT / relative).is_file():
                    raise SystemExit(f"{path}: implementation target not found: {relative}")

        transport = profile["transport"]
        if transport.get("type") == "ble":
            for field in ("service_uuid", "characteristic_uuid", "auto_discovery"):
                if field not in transport:
                    raise SystemExit(f"{path}: BLE transport missing {field}")

    print(f"Validated {len(profiles)} supported-device profile(s)")


if __name__ == "__main__":
    main()

