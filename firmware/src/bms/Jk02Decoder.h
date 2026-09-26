#pragma once

#include <Arduino.h>

#include "BatteryTelemetry.h"

namespace jkbmsr {

// JK-BMS BLE ("JK02") protocol frames: 300 bytes, 0x55 0xAA 0xEB 0x90 header,
// additive 8-bit checksum in the final byte. Two register layouts exist:
// hardware version < 11 uses the 24-cell layout, >= 11 the 32-cell layout
// (same fields shifted by 16 bytes in the first half and 32 in the second).
// Layout ported from syssi/esphome-jk-bms (Apache-2.0).
constexpr size_t kJk02FrameSize = 300;

enum class Jk02FrameType : uint8_t {
  kSettings = 0x01,
  kCellInfo = 0x02,
  kDeviceInfo = 0x03,
  kUnknown = 0xFF,
};

struct Jk02DeviceInfo {
  String vendorId;
  String hardwareVersion;
  String softwareVersion;
  String deviceName;
  bool is32s = false;
  bool valid = false;
};

uint8_t jk02Checksum(const uint8_t* data, size_t length);
// Header + checksum validation for an assembled 300-byte frame.
bool jk02FrameValid(const uint8_t* frame, size_t length);
Jk02FrameType jk02FrameTypeOf(const uint8_t* frame, size_t length);
bool decodeJk02DeviceInfo(const uint8_t* frame, size_t length, Jk02DeviceInfo& out);
bool decodeJk02CellInfo(const uint8_t* frame, size_t length, bool is32s, BatteryTelemetry& out);

}  // namespace jkbmsr
