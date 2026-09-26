#pragma once

#include <Arduino.h>

#include "BatteryTelemetry.h"
#include "bms/BmsBleClient.h"

namespace jkbmsr {

// BLE client for Lolan BMS packs (service 0xFFE0 / notify 0xFFE1 / control
// 0xFFE2 — the same UUIDs as JK and Topband, plus an 0xFFF0-aliased service
// set on some units; the same shared-profile caveats as every other brand
// here apply, and 0xFFE0 in particular overlaps the JK profile this firmware
// also speaks). Auto-discovery prefers an advertised "lolan" name hint;
// otherwise the frame-validation lock rejects a wrong 0xFFE0 device.
//
// Two requests are cycled one-per-poll-interval: Status (0xC565) then
// CellInfo (0x5B65); both carry the default password (12345678). Responses
// are fixed 40-byte frames for these two; a 108-byte Settings frame is never
// requested. Read-only.
class LolanBmsBleClient : public BmsBleClient {
 public:
  void begin(const String& address) override;
  void stop() override;
  void loop() override;
  bool poll(BatteryTelemetry& telemetry) override;
  BmsBleStatus status() const override;

  void handleNotification(const uint8_t* data, size_t length);

 private:
  static constexpr uint32_t kReconnectIntervalMs = 30000;
  static constexpr uint32_t kSampleFreshMs = 65000;
  static constexpr uint32_t kRequestIntervalMs = 5000;
  static constexpr size_t kAssemblyBufferSize = 128;
  static constexpr uint32_t kFrameValidationTimeoutMs = 20000;
  static constexpr uint8_t kMaxRequests = 2;

  void connectIfDue();
  bool discoverTarget();
  bool sendNextRequest();
  void processFrame(const uint8_t* frame, size_t length);

  bool enabled_ = false;
  bool stackInitialized_ = false;
  String configuredAddress_;
  String targetAddress_;
  uint8_t targetAddressType_ = 0;
  uint32_t lastConnectAttemptMs_ = 0;
  uint32_t lastRequestMs_ = 0;
  uint32_t connectedAtMs_ = 0;
  bool frameValidatedSinceConnect_ = false;
  bool statusValid_ = false;
  String excludedAddress_;
  uint16_t requestQueue_[kMaxRequests] = {};
  uint8_t requestPos_ = 0;
  uint8_t assemblyBuffer_[kAssemblyBufferSize] = {};
  size_t assemblyLength_ = 0;
  BatteryTelemetry latest_;
  BmsBleStatus status_;
  void* client_ = nullptr;  // NimBLEClient*, kept opaque to this header
};

}  // namespace jkbmsr