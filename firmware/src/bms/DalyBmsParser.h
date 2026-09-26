#pragma once

#include <Arduino.h>
#include "BatteryTelemetry.h"
#include "bms/BmsUartClient.h"

namespace jkbmsr {

// Daly Smart BMS UART client (0xA5-framed protocol, the classic consumer
// "J/T/A/U/W/ND series" family — NOT the newer 0xD2/Modbus H/K/M/S-series,
// which is a different, incompatible protocol). Ported from the official
// "Daly UART/485 Communications Protocol V1.2" document as implemented by
// maland16/daly-bms-uart (MIT) — see docs/third-party-attribution.md.
//
// Unlike JK-BMS's single "read all registers" exchange, Daly's classic
// protocol is one fixed 13-byte request/response pair per command. A single
// poll() issues five sequential commands (0x90 voltage/current/SOC, 0x91
// min/max cell voltage, 0x92 temperature, 0x93 MOS/charge status, 0x94 cell
// count/cycles) and merges their responses into one BatteryTelemetry sample.
//
// Deliberately not implemented in this first pass (left for a follow-up):
// per-cell voltage array (0x95, a multi-frame response — 3 cells per frame),
// per-sensor temperatures (0x96, also multi-frame), cell balance state
// (0x97), and failure codes (0x98). cellCount is left at 0 rather than
// reporting a count with no matching voltages, since a nonzero count with an
// empty array would look like a data bug rather than an unimplemented field.
class DalyBmsParser : public BmsUartClient {
 public:
  void begin(Stream& serial) override;
  bool poll(BatteryTelemetry& telemetry) override;
  void setRawCaptureEnabled(bool enabled) override;
  BmsUartStatus status() const override;

  // Parses one complete 13-byte response frame for the given command,
  // merging the fields it carries into `telemetry` (a poll() cycle calls
  // this once per command, accumulating into one sample). Static and
  // hardware-free so embedded tests can exercise it with fixtures.
  static bool parseFrame(const uint8_t* frame, size_t length, uint8_t expectedCommand,
                          BatteryTelemetry& telemetry);

 private:
  static constexpr size_t kFrameSize = 13;
  // Generous for a single 13-byte exchange at 9600 baud (~14ms of wire time).
  static constexpr uint32_t kFrameTimeoutMs = 500;
  Stream* serial_ = nullptr;
  BmsUartStatus status_;

  void sendCommand(uint8_t command);
  // Reads exactly one 13-byte frame within kFrameTimeoutMs, resyncing on the
  // 0xA5 header. Returns true and fills buffer on success.
  bool receiveFrame(uint8_t* buffer);
};

}  // namespace jkbmsr
