#pragma once

#include <Arduino.h>
#include "BatteryTelemetry.h"

namespace jkbmsr {

// KS48100 BMS protocol (service 0xFF00 / notify 0xFF01 / control 0xFF02 —
// see KsBmsBleClient). Frames:
//  request:  7B <frameType> 00 7D            (status, cell voltages, config)
//  response: 7B <frameType> <len> [payload] 7D   with total length == len+4
// No checksum — validated by exact length + start/end markers only. All
// multi-byte values are big-endian. Ported from syssi/esphome-ks-bms's
// ks_bms_ble.cpp (Apache-2.0) — see docs/third-party-attribution.md and
// docs/brand-protocols/ks-bms.md.
//
// Decoded frames: Status (0x01; 0x61 layout-identical variant for device
// type 2 is accepted too) and Cell Voltages (0x02). Config/settings frames
// and all register writes are not implemented (read-only telemetry).
class KsBmsDecoder {
 public:
  static constexpr size_t kRequestFrameSize = 4;
  static constexpr uint8_t kFrameTypeStatus = 0x01;
  static constexpr uint8_t kFrameTypeStatusType2 = 0x61;
  static constexpr uint8_t kFrameTypeCellVoltages = 0x02;
  static constexpr uint8_t kFrameStart = 0x7B;
  static constexpr uint8_t kFrameEnd = 0x7D;
  static constexpr uint8_t kMaxKsCells = 24;

  // Builds `7B <frameType> 00 7D`.
  static void buildCommandFrame(uint8_t frame[kRequestFrameSize], uint8_t frameType);

  // A complete frame iff start/end markers match and length == data[2]+4.
  static bool isCompleteFrame(const uint8_t* frame, size_t length);

  static bool parseStatusFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry);
  // Parses the Cell Voltages frame (0x02) into telemetry.cellVoltages and
  // recomputes the min/max/avg/delta cell statistics.
  static bool parseCellVoltagesFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry);
};

}  // namespace jkbmsr