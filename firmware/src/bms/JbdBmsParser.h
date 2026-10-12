#pragma once

#include <Arduino.h>
#include "BatteryTelemetry.h"

namespace jkbmsr {

// JBD (Jiabaida) frame decoder. Speaks the 0xDD...0x77-framed
// request/response protocol shared with several JBD-rebrand products
// (Xiaoxiang, Overkill Solar, LLT Power). Ported from
// syssi/esphome-jbd-bms's components/jbd_bms/jbd_bms.cpp (Apache-2.0) — see
// docs/third-party-attribution.md.
//
// This is the shared decode half of the JBD BLE transport: JbdBmsBleClient
// reassembles 0xFF00/0xFF01/0xFF02 notifications into a complete frame and
// hands it to parseFrame(). There is no wired transport — the BMS link is
// Bluetooth only.
//
// A complete read is two frames: 0x03 (hardware info — pack
// voltage/current/SOC/capacity/cycles/protection status/temperatures) and
// 0x04 (cell info — individual cell voltages, one 2-byte value per cell in a
// single response frame, unlike Daly's multi-frame cell command).
class JbdBmsParser {
 public:
  // Parses one complete frame (0xDD header through the 0x77 trailer),
  // merging the fields it carries into `telemetry`. Static and hardware-free
  // so embedded tests can exercise it with fixtures.
  static bool parseFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry);
};

}  // namespace jkbmsr
