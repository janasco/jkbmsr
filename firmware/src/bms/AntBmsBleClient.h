#pragma once

#include <Arduino.h>

#include "BatteryTelemetry.h"
#include "bms/BmsBleClient.h"

namespace jkbmsr {

// BLE client for ANT BMS packs speaking the 2021 protocol (service 0xFFE0, a
// single characteristic 0xFFE1 used for both writes and notifications — like
// JkBmsBleClient's classic profile, there is no separate control
// characteristic). NOTE: service 0xFFE0 is shared with JK, Topband and Lolan;
// auto-discovery checks the advertised name for an "ant" hint and otherwise
// falls back to the strongest 0xFFE0 advertiser, backed by the frame-
// validation lock: a connection that never decodes an ANT frame within
// kFrameValidationTimeoutMs is treated as a wrong-device lock and retried
// against the next candidate — see loop(). Configure an explicit
// bmsBleAddress when several 0xFFE0 vendors might be present.
//
// A single status request returns cells, temps, pack voltage/current/SOC/SOH
// and MOS state in one frame, so the protocol is stateless: unlike the
// multi-frame brands in this milestone there is no cell-chunk merge.
class AntBmsBleClient : public BmsBleClient {
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
  static constexpr size_t kAssemblyBufferSize = 256;
  static constexpr uint32_t kFrameValidationTimeoutMs = 20000;

  void connectIfDue();
  bool discoverTarget();
  bool sendStatusRequest();
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
  String excludedAddress_;
  uint8_t assemblyBuffer_[kAssemblyBufferSize] = {};
  size_t assemblyLength_ = 0;
  BatteryTelemetry latest_;
  BmsBleStatus status_;
  void* client_ = nullptr;  // NimBLEClient*, kept opaque to this header
};

}  // namespace jkbmsr