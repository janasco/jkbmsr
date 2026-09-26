#pragma once

#include <Arduino.h>
#include "BatteryTelemetry.h"

namespace jkbmsr {

// Shared shape for every vendor's wired UART client (JkBmsParser,
// DalyBmsParser, JbdBmsParser) so main.cpp can dispatch on config.bmsVendor
// through one interface instead of a parser-per-vendor if/else at every call
// site. BLE stays vendor-specific for now (only JK has a BLE client) — this
// interface intentionally covers UART only.
struct BmsUartStatus {
  uint32_t lastFrameAtMs = 0;
  uint32_t parseErrors = 0;
  uint32_t bytesReceived = 0;
  // Bytes that arrived after a poll window closed (drained before the next
  // request). Growth here means the BMS responds slower than the window.
  uint32_t staleBytes = 0;
  bool rawCaptureEnabled = false;
};

class BmsUartClient {
 public:
  virtual ~BmsUartClient() = default;
  // Stream, not HardwareSerial, so a target without a free hardware UART for
  // BMS traffic (e.g. ESP8266 — see env:esp8266-nodemcu) can pass a
  // SoftwareSerial instance instead; HardwareSerial itself still works
  // unchanged since it derives from Stream too.
  virtual void begin(Stream& serial) = 0;
  // Sends a status request and waits for a valid response frame. Returns
  // true and fills telemetry on success.
  virtual bool poll(BatteryTelemetry& telemetry) = 0;
  virtual void setRawCaptureEnabled(bool enabled) = 0;
  virtual BmsUartStatus status() const = 0;
};

// Hex-dumps one frame to Serial when raw capture is enabled — the debugging
// hook that lets a real hardware session be turned into a regression fixture
// (see any devices/*/fixtures/README.md). Shared by DalyBmsParser and
// JbdBmsParser; JkBmsParser predates this and keeps its own copy.
inline void emitBmsRawCapture(const char* label, const uint8_t* data, size_t length, bool enabled) {
  if (!enabled || data == nullptr || length == 0) {
    return;
  }
  Serial.print(label);
  Serial.print(" ");
  Serial.print(millis());
  Serial.print(" ");
  Serial.print(length);
  Serial.print(" ");
  for (size_t index = 0; index < length; ++index) {
    if (data[index] < 0x10) {
      Serial.print("0");
    }
    Serial.print(data[index], HEX);
    if (index + 1 < length) {
      Serial.print(" ");
    }
  }
  Serial.println();
}

}  // namespace jkbmsr
