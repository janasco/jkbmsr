#pragma once

#include <Arduino.h>

#include "BatteryTelemetry.h"
#include "bms/BmsBleClient.h"

namespace jkbmsr {

// BLE client for Daly BMS packs speaking the D2/Modbus protocol (service
// 0xFFF0, notify characteristic 0xFFF1, write/control characteristic
// 0xFFF2 — two characteristics, unlike JK's single one). Unlike
// JkBmsBleClient, no device-info handshake is needed first: the status
// response (DalyD2Decoder) is self-describing, so a status request is sent
// immediately on connect. Disabled unless begin() is called with a target
// address; all radio work happens in loop().
class DalyBmsBleClient : public BmsBleClient {
 public:
  // An empty address enables auto-discovery of the strongest nearby unit
  // (matching service UUID 0xFFF0 or an advertised name starting "DL").
  void begin(const String& address) override;
  void stop() override;
  void loop() override;
  bool poll(BatteryTelemetry& telemetry) override;
  BmsBleStatus status() const override;

  // Called from the NimBLE notification callback; reassembles chunked
  // notifications into a complete status response frame.
  void handleNotification(const uint8_t* data, size_t length);

 private:
  static constexpr uint32_t kReconnectIntervalMs = 30000;
  static constexpr uint32_t kSampleFreshMs = 65000;
  static constexpr uint32_t kRequestIntervalMs = 5000;
  // Target reassembly size: exactly what a 62-register status request
  // should produce. Units that ignore the requested count and answer with
  // 80 registers instead (165 bytes) aren't handled by this transport in
  // this pass — DalyD2Decoder itself supports decoding that size if fed a
  // full frame directly (e.g. from a manually captured fixture).
  static constexpr size_t kAssemblyTargetSize = 129;
  static constexpr size_t kAssemblyBufferSize = 192;

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
  uint8_t assemblyBuffer_[kAssemblyBufferSize] = {};
  size_t assemblyLength_ = 0;
  BatteryTelemetry latest_;
  BmsBleStatus status_;
  void* client_ = nullptr;  // NimBLEClient*, kept opaque to this header
};

}  // namespace jkbmsr
