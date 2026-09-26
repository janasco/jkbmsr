#pragma once

#include <Arduino.h>
#include "BatteryTelemetry.h"
#include "bms/BmsUartClient.h"

namespace jkbmsr {

// JK-BMS UART-TTL ("GPS" port) client. Speaks the 0x4E57-framed protocol used
// by every JK-BMS with software version >= 6.0: sends a "read all registers"
// request (command 0x06) and decodes the positional register layout of the
// response. Register map ported from syssi/esphome-jk-bms (Apache-2.0).
class JkBmsParser : public BmsUartClient {
 public:
  void begin(Stream& serial) override;
  // Sends a status request and waits up to kResponseTimeoutMs for a valid
  // response frame. Returns true and fills telemetry on success.
  bool poll(BatteryTelemetry& telemetry) override;
  void setRawCaptureEnabled(bool enabled) override;
  BmsUartStatus status() const override;
  // Parses one complete raw frame (header through checksum). Static and
  // hardware-free so embedded tests can exercise it with fixtures.
  static bool parseFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry);

 private:
  // Response is ~285 bytes for 14 cells and grows 3 bytes per cell
  // (~340 bytes at the 32-cell maximum).
  static constexpr size_t kBufferSize = 384;
  // Generous: a full response is ~25ms of wire time at 115200, but some packs
  // answer noticeably late and a missed window costs a whole telemetry cycle.
  static constexpr uint32_t kResponseTimeoutMs = 1500;
  Stream* serial_ = nullptr;
  uint8_t buffer_[kBufferSize] = {};
  size_t bufferLength_ = 0;
  BmsUartStatus status_;

  void sendStatusRequest();
  // Drops leading bytes until the buffer starts with the 0x4E 0x57 header.
  void resyncBuffer(size_t dropAtLeast);
  void emitRawCapture(const char* label, const uint8_t* data, size_t length) const;
};

}  // namespace jkbmsr
