#pragma once

#include <Arduino.h>
#include "BatteryTelemetry.h"

namespace jkbmsr {

// Basen BMS protocol (service 0xFA00 / notify 0xFA01 / control 0xFA02 — see
// BasenBmsBleClient). Frame envelope:
//  [SOF: 0x3A poll | 0x3B write/immediate] [addr 0x16] [func] [len] [payload...]
//  [sumLo sumHi] 0D 0A
// Checksum is a PLAIN 16-bit accumulator over frame[1 .. 3+len] (addr+func+
// len+payload) — a simple sum, not a CRC — verified against
// BasenBmsBle::chksum_ (kept explicit here because every other milestone-1
// brand uses a CRC). All telemetry multi-byte values are LITTLE-endian (the
// odd-one-out among the five brands). Ported from
// syssi/esphome-basen-bms's basen_bms_ble.cpp (Apache-2.0) — see
// docs/third-party-attribution.md and docs/brand-protocols/basen-bms.md.
//
// Decoded frames: Status (0x2A), General Info (0x2B), and the two
// Cell-Voltages chunks (0x24 = cells 1-12, 0x25 = cells 13-24). Read-only.
class BasenBmsDecoder {
 public:
  static constexpr uint8_t kFrameTypeStatus = 0x2A;
  static constexpr uint8_t kFrameTypeGeneralInfo = 0x2B;
  static constexpr uint8_t kFrameTypeCellVoltages1_12 = 0x24;
  static constexpr uint8_t kFrameTypeCellVoltages13_24 = 0x25;
  // Each cell-voltage frame type carries at most 12 cells (24 payload bytes).
  static constexpr uint8_t kCellsPerChunk = 12;
  static constexpr size_t kMaxRequestFrameSize = 8;  // full envelope, payload len 0

  // Builds a poll request `3A 16 <frameType> 00 <sumLo sumHi> 0D 0A` (syssi's
  // build_frame_ with an empty payload — the queued-command form).
  static void buildRequestFrame(uint8_t frame[kMaxRequestFrameSize], uint8_t frameType);

  // If the buffered bytes hold a complete envelope (SOF, declared length, and
  // 0D 0A trailer present), returns its total frame length; 0 otherwise. Used
  // by the client for MTU-split reassembly.
  static size_t frameCompleteLength(const uint8_t* frame, size_t length);

  // Verifies the plain 16-bit sum over frame[1 .. 3+len] against the stored
  // little-endian value.
  static bool validateChecksum(const uint8_t* frame, size_t frameLen);

  static bool parseStatusFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry);
  static bool parseGeneralInfoFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry);
  // Parses one cell-voltage chunk (0x24 => cells 1-12, 0x25 => 13-24) into
  // telemetry.cellVoltages at the chunk's offset, merges cellCount, and
  // recomputes the min/max/avg/delta cell statistics.
  static bool parseCellChunkFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry);
};

}  // namespace jkbmsr