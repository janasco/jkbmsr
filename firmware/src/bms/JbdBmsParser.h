#pragma once

#include <Arduino.h>
#include "BatteryTelemetry.h"
#include "bms/BmsUartClient.h"

namespace jkbmsr {

// JBD (Jiabaida) BMS UART-TTL client. Speaks the 0xDD...0x77-framed
// request/response protocol shared with several JBD-rebrand products
// (Xiaoxiang, Overkill Solar, LLT Power). Ported from
// syssi/esphome-jbd-bms's components/jbd_bms/jbd_bms.cpp (Apache-2.0) — see
// docs/third-party-attribution.md.
//
// A poll() issues two sequential commands: 0x03 (hardware info — pack
// voltage/current/SOC/capacity/cycles/protection status/temperatures) and
// 0x04 (cell info — individual cell voltages, one 2-byte value per cell in a
// single response frame, unlike Daly's multi-frame cell command). Unlike
// DalyBmsParser, this pilot's JBD support decodes the full per-cell voltage
// array since JBD's protocol makes that a single extra request rather than
// several.
class JbdBmsParser : public BmsUartClient {
 public:
  void begin(Stream& serial) override;
  bool poll(BatteryTelemetry& telemetry) override;
  void setRawCaptureEnabled(bool enabled) override;
  BmsUartStatus status() const override;

  // Parses one complete frame (0xDD header through the 0x77 trailer),
  // merging the fields it carries into `telemetry`. Static and hardware-free
  // so embedded tests can exercise it with fixtures.
  static bool parseFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry);

 private:
  // Cell-info frame for 32 cells is 4 + 64 + 3 = 71 bytes; hardware-info is
  // fixed at ~34 bytes. Generous headroom for both.
  static constexpr size_t kBufferSize = 128;
  static constexpr uint32_t kFrameTimeoutMs = 500;
  static constexpr uint8_t kCmdHardwareInfo = 0x03;
  static constexpr uint8_t kCmdCellInfo = 0x04;
  Stream* serial_ = nullptr;
  BmsUartStatus status_;

  void sendReadCommand(uint8_t address);
  // Reads one complete variable-length frame within kFrameTimeoutMs,
  // resyncing on the 0xDD header. Returns the frame length, or 0 on timeout.
  size_t receiveFrame(uint8_t* buffer);
};

}  // namespace jkbmsr
