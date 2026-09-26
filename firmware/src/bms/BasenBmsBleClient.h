#pragma once

#include <Arduino.h>

#include "BatteryTelemetry.h"
#include "bms/BmsBleClient.h"

namespace jkbmsr {

// BLE client for Basen/VIP/EE/Mabru/Roamer BMS packs (service 0xFA00 /
// notify 0xFA01 / control 0xFA02 — a service UUID unique to this family
// among the milestone brands, so shared-UUID mis-discovery is less likely;
// the frame-validation lock still applies). Auto-discovery prefers an
// advertised "basen" name hint.
//
// Telemetry is spread across four requests, cycled one-per-poll-interval:
// Status (0x2A) first, General Info (0x2B, cycle count + capacities), then
// the two Cell-Voltages chunks (0x24 = cells 1-12, 0x25 = 13-24). Frames are
// trailer-driven (0D 0A) and reassembled across MTU splits. Read-only.
class BasenBmsBleClient : public BmsBleClient {
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
  static constexpr uint8_t kMaxRequests = 4;

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
  uint8_t requestQueue_[kMaxRequests] = {};
  uint8_t requestPos_ = 0;
  uint8_t assemblyBuffer_[kAssemblyBufferSize] = {};
  size_t assemblyLength_ = 0;
  BatteryTelemetry latest_;
  BmsBleStatus status_;
  void* client_ = nullptr;  // NimBLEClient*, kept opaque to this header
};

}  // namespace jkbmsr