#pragma once

#include <Arduino.h>

#include "BatteryTelemetry.h"
#include "bms/BmsBleClient.h"

namespace jkbmsr {

// BLE client for Tianpower BMS packs (service 0xFF00 / notify 0xFF01 /
// control 0xFF02 — the same UUIDs as JBD, Seplos and KS48100). Auto-discovery
// prefers an advertised "tianpower" name hint; otherwise the valid-frame lock
// (loop()) rejects a connected-but-never-decoding device within
// kFrameValidationTimeoutMs, since the shared service can't tell brands apart.
// Configure an explicit bmsBleAddress when several 0xFF00 vendors may be near.
//
// Telemetry is spread across three requests, cycled one-per-poll-interval:
// Status (0x83) first, then the two Cell-Voltages chunk frames (0x88, 0x89).
// The Status frame carries pack voltage/current/SOC and the temps; cell
// chunks are merged into the working telemetry on arrival. Read-only.
class TianpowerBmsBleClient : public BmsBleClient {
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
  static constexpr size_t kAssemblyBufferSize = 64;
  static constexpr uint32_t kFrameValidationTimeoutMs = 20000;
  static constexpr uint8_t kMaxRequests = 3;

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