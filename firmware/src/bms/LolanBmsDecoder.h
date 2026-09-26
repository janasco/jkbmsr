#pragma once

#include <Arduino.h>
#include "BatteryTelemetry.h"

namespace jkbmsr {

// Lolan BMS protocol (service 0xFFE0 / notify 0xFFE1 / control 0xFFE2 — see
// LolanBmsBleClient; a 0xFFF0/0xFFF1/0xFFF2 alias service exists on some
// units). Request: [fnHi fnLo] [password 4 bytes BE] (6 bytes, no checksum).
// Response: [frameType] 0x00 [payload...]; Status (0x01) and CellInfo (0x02)
// are fixed 40-byte frames, Settings (0x03) is 108 bytes. No checksum on
// status/cell-info (only the separate Settings frame is checksummed, with the
// custom crc16_lolan — not requested here). All numeric values are IEEE-754
// float32, big-endian. Ported from syssi/esphome-lolan-bms's
// lolan_bms_ble.cpp (Apache-2.0) — see docs/third-party-attribution.md and
// docs/brand-protocols/lolan-bms.md.
//
// Decoded frames: Status (0xC565 request) and CellInfo (0x5B65 request).
// Switch writes reuse the same request mechanism with distinct turn-on/turn-
// off function codes — not implemented (read-only telemetry).
class LolanBmsDecoder {
 public:
  static constexpr size_t kRequestFrameSize = 6;
  static constexpr uint16_t kCommandStatus = 0xC565;
  static constexpr uint16_t kCommandCellInfo = 0x5B65;
  static constexpr uint32_t kDefaultPassword = 12345678;
  static constexpr uint8_t kFrameTypeStatus = 0x01;
  static constexpr uint8_t kFrameTypeCellInfo = 0x02;
  static constexpr uint8_t kFrameTypeSettings = 0x03;
  static constexpr size_t kStatusFrameSize = 40;

  // Builds `[fnHi fnLo] [pw>>24 pw>>16 pw>>8 pw>>0]`.
  static void buildCommandFrame(uint8_t frame[kRequestFrameSize], uint16_t command, uint32_t password);

  // Total response size for a frame whose first byte is its type (40 for
  // status/cell-info, 108 for settings), or 0 if the buffered bytes don't yet
  // start a recognized frame.
  static size_t responseSizeFor(const uint8_t* frame, size_t length);

  // Big-endian IEEE-754 float32.
  static float beFloat32(const uint8_t* p);

  static bool parseStatusFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry);
  // Parses the CellInfo frame (0x02) into telemetry.cellVoltages and recomputes
  // the min/max/avg/delta cell statistics.
  static bool parseCellInfoFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry);
};

}  // namespace jkbmsr