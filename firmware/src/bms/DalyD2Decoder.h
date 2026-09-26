#pragma once

#include <Arduino.h>
#include "BatteryTelemetry.h"

namespace jkbmsr {

// Daly's BLE protocol (service 0xFFF0, notify 0xFFF1, control 0xFFF2 —
// see DalyBmsBleClient), frame start 0xD2, Modbus-style function/register
// reads with a CRC16-Modbus checksum. This is a DIFFERENT, incompatible
// wire protocol from DalyBmsParser's UART 0xA5 framing — same brand, two
// unrelated protocol families (H/K/M/S-series BLE vs. classic
// J/T/A/U/W/ND-series UART). Ported from syssi/esphome-daly-bms's
// daly_bms_ble.cpp (Apache-2.0) — see docs/third-party-attribution.md.
//
// Only the "status" register range (address 0x0000) is implemented — a
// single request returns cell voltages, temperatures, pack
// voltage/current/SOC, cycle count, and charge/discharge/balance state all
// at once (unlike the UART protocol's 5 separate commands). Settings,
// version, and balancer-switch commands are not implemented, nor is the
// separate "P81" protocol variant (frame start 0x81/0x51) some Daly BLE
// units use instead of this one.
class DalyD2Decoder {
 public:
  // Number of 16-bit registers to request in the status read. 62 is the
  // universal minimum (129-byte response); some units answer with 80
  // registers instead (165 bytes) and get a few extra fields — see
  // parseStatusFrame.
  static constexpr uint16_t kStatusRegisterCount = 62;

  // Builds the 8-byte "read status registers" request frame.
  static void buildStatusRequest(uint8_t frame[8]);

  // Parses one complete status response frame (0xD2 header through the
  // CRC16 trailer) into telemetry. Accepts either the 62-register
  // (129-byte) or 80-register (165-byte) response size; the larger size
  // additionally carries balancing current, MOSFET temperature, and board
  // temperature. Static and hardware-free so embedded tests can exercise
  // it with fixtures.
  static bool parseStatusFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry);

  // Standard CRC16-Modbus (polynomial 0xA001, init 0xFFFF), little-endian
  // in the frame (low byte first). Not available as a library here, so
  // implemented directly — same as every other checksum in this codebase.
  static uint16_t crc16Modbus(const uint8_t* data, size_t length);
};

}  // namespace jkbmsr
