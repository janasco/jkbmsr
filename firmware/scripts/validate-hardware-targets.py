#!/usr/bin/env python3
"""Validate that public hardware metadata matches PlatformIO build targets."""

import configparser
import json
import sys
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(f"validate-hardware-targets: {message}")


root = Path(__file__).resolve().parent.parent
catalog = json.loads((root / "hardware-targets.json").read_text(encoding="utf-8"))
if catalog.get("schemaVersion") != 1:
    fail("unsupported schemaVersion")

parser = configparser.ConfigParser(interpolation=None)
parser.read(root / "platformio.ini", encoding="utf-8")

seen_targets: set[str] = set()
for target in catalog.get("targets", []):
    name = target.get("targetHardware", "")
    environment = target.get("platformioEnvironment", "")
    family = target.get("chipFamily", "")
    if not name or name in seen_targets:
        fail(f"missing or duplicate targetHardware: {name!r}")
    # chipFamily is the underlying silicon (e.g. "ESP32"), not unique per
    # target — a single chip can legitimately back multiple hardware targets
    # that differ by flash size or board layout (e.g. esp32-classic-4mb and
    # esp32-classic-8mb both report chipFamily "ESP32"). Only targetHardware
    # itself needs to be unique, checked above.
    if not family:
        fail(f"{name} missing chipFamily")
    if f"env:{environment}" not in parser:
        fail(f"{name} references missing PlatformIO environment {environment!r}")
    capabilities = target.get("capabilities", {})
    if set(capabilities) != {"wifi", "uart", "ble", "ota"}:
        fail(f"{name} must declare wifi, uart, ble, and ota capabilities")
    uart = target.get("defaultUart", {})
    if set(uart) != {"rxPin", "txPin", "baudRate"} or uart["rxPin"] == uart["txPin"]:
        fail(f"{name} must declare distinct default UART pins and a baud rate")
    if target.get("releaseStatus") not in {"supported", "experimental"}:
        fail(f"{name} has invalid releaseStatus")
    seen_targets.add(name)

if not seen_targets:
    fail("catalog contains no targets")

print(f"validate-hardware-targets: validated {len(seen_targets)} targets")
