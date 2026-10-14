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

// --- Raw-capture diagnostics --------------------------------------------
//
// When a cell-info frame is dropped or fails to verify/decode, the client
// logs the raw frame so a capture can come from the board's own serial
// instead of a phone/nRF Connect session. Two pure helpers live here (rather
// than only in the BLE client) so the host suite exercises them without the
// ESP toolchain: hex formatting, and the rate gate that keeps a stream of
// corrupt or all-zero frames from flooding the log.

// Lowercase hex expansion of `frame`, no separators, no prefix. A full
// 300-byte frame becomes 600 characters; nullptr yields an empty string.
String jk02FrameToHex(const uint8_t* frame, size_t length);

// True when `mask` has a hole below its highest set bit — i.e. it is not a
// contiguous run of ones from bit 0. A frame with a gap cannot be represented
// by the dense cellVoltages array (the absent slot reads as 0.0 V), so the
// caller treats it as an anomaly worth capturing. `0` (no cells) is not a gap.
bool cellMaskHasGap(uint32_t mask);

// Rate gate for the raw-capture log. Frames arrive at ~1-2/s, so an
// unconditional log would spam; but the FIRST frame MUST be captured — a
// suppressed first frame would hide the exact event the log exists for, so
// `everLogged` is tracked separately from the timestamp instead of treating
// `lastLoggedAtMs == 0` as "never". Pure: a function of the call timestamps
// only, so it is host-tested in both directions.
struct Jk02RawCaptureGate {
  static constexpr uint32_t kDefaultMinIntervalMs = 5000;

  explicit Jk02RawCaptureGate(uint32_t minIntervalMs = kDefaultMinIntervalMs)
      : minIntervalMs_(minIntervalMs) {}

  // Returns true when a line is due at `nowMs`; false means suppressed, and
  // the running suppression count is available for a "+N suppressed" suffix.
  bool shouldLog(uint32_t nowMs) {
    if (everLogged_ && nowMs - lastLoggedAtMs_ < minIntervalMs_) {
      suppressed_ += 1;
      return false;
    }
    everLogged_ = true;
    lastLoggedAtMs_ = nowMs;
    return true;
  }

  uint32_t suppressedCount() const { return suppressed_; }
  uint32_t takeSuppressedCount() {
    const uint32_t count = suppressed_;
    suppressed_ = 0;
    return count;
  }

 private:
  uint32_t minIntervalMs_;
  bool everLogged_ = false;
  uint32_t lastLoggedAtMs_ = 0;
  uint32_t suppressed_ = 0;
};

}  // namespace jkbmsr
