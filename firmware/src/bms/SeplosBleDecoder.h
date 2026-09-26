#pragma once

#include <Arduino.h>
#include "BatteryTelemetry.h"

namespace jkbmsr {

// Seplos's BLE protocol (service 0xFF00, notify 0xFF01, control 0xFF02 —
// see SeplosBmsBleClient), frame start 0x7E / end 0x0D, CRC-16/XMODEM
// checksum. Covers the 1101-SPxx/ZH/MZ family (the best-evidenced Seplos
// BLE protocol, per community reports). The separate, much-less-proven
// V3/EMU10xx protocol variant is NOT implemented. Ported from
// syssi/esphome-seplos-bms's seplos_bms_ble.cpp (Apache-2.0) — see
// docs/third-party-attribution.md.
//
// Only the "single machine data" command (0x61) is implemented — a single
// request returns cell voltages, temperatures, pack voltage/current/SOC,
// capacity, cycle count, state of health, and switch/alarm state all at
// once. Manufacturer-info, settings, parallel-data, and all write/control
// commands are not implemented.
class SeplosBleDecoder {
 public:
  // Total size of the "single machine data" request frame: 7-byte header
  // + 1-byte payload (device address 0x00) + 2-byte CRC + 1-byte EOF.
  static constexpr size_t kRequestFrameSize = 11;

  // Builds the complete request frame for SEPLOS_CMD_GET_SINGLE_MACHINE_DATA.
  static void buildSingleMachineDataRequest(uint8_t frame[kRequestFrameSize]);

  // Parses one complete "single machine data" response frame (0x7E header
  // through the 0x0D end marker) into telemetry. Static and hardware-free
  // so embedded tests can exercise it with fixtures.
  static bool parseSingleMachineDataFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry);

  // CRC-16/XMODEM (polynomial 0x1021, init 0x0000, MSB-first, not
  // reflected). Not available as a library here, so implemented directly —
  // same as every other checksum in this codebase.
  static uint16_t crc16Xmodem(const uint8_t* data, size_t length);
};

}  // namespace jkbmsr
