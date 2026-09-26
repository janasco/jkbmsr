#pragma once

#include <Arduino.h>
#include "BatteryTelemetry.h"

namespace jkbmsr {

// ANT BMS "2021" protocol (service 0xFFE0, single characteristic 0xFFE1 for
// both writes and notifications — see AntBmsBleClient). Frame:
//  7E A1 [function] [addrLo addrHi] [len] [payload...] [crcLo crcHi] AA 55
// CRC-16/MODBUS over raw[1 .. frameLen-5], stored little-endian. Ported from
// syssi/esphome-ant-bms's ant_bms_ble.cpp and ant_bms.cpp (Apache-2.0) — see
// docs/third-party-attribution.md and docs/brand-protocols/ant-bms.md.
//
// Only the 2021 status response (function 0x11, answering a status request
// with function 0x01) is decoded: it carries cells, up to 4 NTC temps, the
// MOSFET/balancer temps, pack voltage/current/SOC/SOH, MOS states, balancing
// state, protections, and capacities all in one frame. Write/control commands
// are not implemented (read-only telemetry).
class AntBmsDecoder {
 public:
  // Total size of a status request frame: 7E A1 01 00 00 BE <crc lo hi> AA 55.
  static constexpr size_t kRequestFrameSize = 10;

  // Builds the complete 2021 status request (function 0x01, address 0x0000).
  static void buildStatusRequest(uint8_t frame[kRequestFrameSize]);

  // Parses one complete 2021 status response frame (0x7E header through the
  // ending AA 55) into telemetry. Static and hardware-free so embedded tests
  // can exercise it with fixtures. Returns false on any byte/CRC mismatch.
  static bool parseStatusFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry);

  // CRC-16/MODBUS (polynomial 0xA001, reflected, init 0xFFFF). Not available
  // as a library here, so implemented directly — same as every other checksum
  // in this codebase.
  static uint16_t crc16Modbus(const uint8_t* data, size_t length);
};

}  // namespace jkbmsr