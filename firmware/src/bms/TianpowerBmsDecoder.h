#pragma once

#include <Arduino.h>
#include "BatteryTelemetry.h"

namespace jkbmsr {

// Tianpower BMS protocol (service 0xFF00 / notify 0xFF01 / control 0xFF02 —
// see TianpowerBmsBleClient). Fixed 20-byte response frames:
//  55 14 <frameType> ... AA
// No checksum — start/end markers and length are the only validation. All
// multi-byte values are big-endian. Ported from
// syssi/esphome-tianpower-bms's tianpower_bms_ble.cpp (Apache-2.0) — see
// docs/third-party-attribution.md and docs/brand-protocols/tianpower-bms.md.
//
// Only the Status frame (0x83) and the two Cell-Voltages chunk frames (0x88
// = cells 1-8, 0x89 = cells 9-16) are decoded; the Status frame already
// carries total voltage, current, SOC and the average/ambient/MOSFET temps,
// so the separate Temperatures frame (0x87) is not requested. Read-only.
class TianpowerBmsDecoder {
 public:
  static constexpr size_t kRequestFrameSize = 4;
  static constexpr uint8_t kFrameTypeStatus = 0x83;
  static constexpr uint8_t kFrameTypeCellVoltages1_8 = 0x88;
  static constexpr uint8_t kFrameTypeCellVoltages9_16 = 0x89;
  static constexpr size_t kResponseFrameSize = 20;

  // Builds `55 04 <frameType> AA`.
  static void buildRequestFrame(uint8_t frame[kRequestFrameSize], uint8_t frameType);

  // True if the buffer is a complete, correctly-marker'd response frame.
  static bool isCompleteFrame(const uint8_t* frame, size_t length);

  // Parses the Status frame (0x83): SOC, pack voltage/current/power, and the
  // three temperatures. Cells are filled by the chunk frames below.
  static bool parseStatusFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry);

  // Parses one cell-voltage chunk frame (0x88 = cells 1-8, 0x89 = 9-16) into
  // telemetry.cellVoltages at the chunk's offset, merges cellCount, and
  // recomputes the min/max/avg/delta cell statistics.
  static bool parseCellChunkFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry);
};

}  // namespace jkbmsr