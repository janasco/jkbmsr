#!/usr/bin/env python3
"""Generate a chip-safe ESP Web Tools manifest for one firmware target."""

import argparse
import json
from pathlib import Path


parser = argparse.ArgumentParser()
parser.add_argument("--target", required=True)
parser.add_argument("--version", required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()

root = Path(__file__).resolve().parent.parent
catalog = json.loads((root / "hardware-targets.json").read_text(encoding="utf-8"))
catalog_target = "esp32-classic-4mb" if args.target == "esp32dev" else args.target
target = next(
    (item for item in catalog["targets"] if item["targetHardware"] == catalog_target),
    None,
)
if target is None:
    raise SystemExit(f"generate-flash-manifest: unknown target {args.target!r}")

family = target["chipFamily"]
if family == "ESP8266":
    parts = [{"path": "./firmware.bin", "offset": 0}]
else:
    bootloader_offset = 4096 if family == "ESP32" else 0
    parts = [
        {"path": "./bootloader.bin", "offset": bootloader_offset},
        {"path": "./partitions.bin", "offset": 32768},
        {"path": "./boot_app0.bin", "offset": 57344},
        {"path": "./firmware.bin", "offset": 65536},
    ]

manifest = {
    "name": "JKBMSR Gateway",
    "version": args.version,
    "new_install_improv_wait_time": 20,
    "builds": [
        {
            "chipFamily": family,
            "targetHardware": args.target,
            "capabilities": target["capabilities"],
            "parts": parts,
        }
    ],
}
args.output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(f"generate-flash-manifest: wrote {args.output} for {args.target} ({family})")
