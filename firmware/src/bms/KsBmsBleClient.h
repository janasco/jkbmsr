#pragma once

#include <Arduino.h>

#include "BatteryTelemetry.h"
#include "bms/BmsBleClient.h"

namespace jkbmsr {

// BLE client for KS48100 BMS packs (service 0xFF00 / notify 0xFF01 /
// control 0xFF02 — the same UUIDs as JBD, Seplos and Tianpower). Auto-
// discovery prefers an advertised name hint ("ks", "ks-", "ks48100");
// otherwise the frame-validation lock rejects a wrong 0xFF00 device.
//
// Two requests are cycled one-per-poll-interval: Status (0x01) then Cell
// Voltages (0x02). Upstream treats each notification as one complete frame
// and does not reassemble — a light accumulator is kept here anyway so an
// MTU-split chunk can't corrupt the parse. Read-only.
class KsBmsBleClient : public BmsBleClient {
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
  uint8_t requestQueue_[kMaxRequests] = {};
  uint8_t requestPos_ = 0;
  uint8_t assemblyBuffer_[kAssemblyBufferSize] = {};
  size_t assemblyLength_ = 0;
  BatteryTelemetry latest_;
  BmsBleStatus status_;
  void* client_ = nullptr;  // NimBLEClient*, kept opaque to this header
};

}  // namespace jkbmsr