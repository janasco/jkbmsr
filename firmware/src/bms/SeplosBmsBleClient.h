#pragma once

#include <Arduino.h>

#include "BatteryTelemetry.h"
#include "bms/BmsBleClient.h"

namespace jkbmsr {

// BLE client for Seplos BMS packs speaking the 1101-SPxx/ZH/MZ protocol
// (service 0xFF00, notify characteristic 0xFF01, control characteristic
// 0xFF02). Note: these are the SAME UUIDs JbdBmsBleClient uses — if both a
// JBD and a Seplos unit are advertising nearby, address-less auto-discovery
// can pick the wrong one. Configure an explicit bmsBleAddress when both
// vendors might be present (upstream's own Seplos integration always
// requires an explicit MAC address for this reason; it has no name-prefix
// heuristic for Seplos the way JK/Daly units do). As a second line of
// defense for auto-discovery, a connection that never produces a valid
// frame within kFrameValidationTimeoutMs is treated as a wrong-device lock
// and retried against the next candidate — see loop().
//
// Unlike JkBmsBleClient, no device-info handshake is needed first: the
// single-machine-data response (SeplosBleDecoder) is self-describing, so a
// request is sent immediately on connect. Disabled unless begin() is
// called with a target address; all radio work happens in loop().
class SeplosBmsBleClient : public BmsBleClient {
 public:
  // An empty address enables auto-discovery of the strongest nearby unit
  // matching service UUID 0xFF00.
  void begin(const String& address) override;
  void stop() override;
  void loop() override;
  bool poll(BatteryTelemetry& telemetry) override;
  BmsBleStatus status() const override;

  // Called from the NimBLE notification callback; reassembles chunked
  // notifications into a complete, variable-length response frame.
  void handleNotification(const uint8_t* data, size_t length);

 private:
  static constexpr uint32_t kReconnectIntervalMs = 30000;
  static constexpr uint32_t kSampleFreshMs = 65000;
  static constexpr uint32_t kRequestIntervalMs = 5000;
  static constexpr size_t kAssemblyBufferSize = 256;
  // Since JBD shares this exact service/characteristic UUID triplet, an
  // auto-discovered "Seplos" connection may actually be a JBD unit — that
  // link stays up at the BLE layer indefinitely (JBD advertises the same
  // 0xFF00/0xFF01/0xFF02 service, so the existing service-check can't tell
  // them apart) while never producing a frame this decoder accepts. If no
  // valid frame decodes within this window after connecting, treat it as a
  // wrong-device lock: disconnect and retry discovery excluding it, rather
  // than sitting connected-but-dead forever.
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
  // Auto-discovered address to skip on the next discoverTarget() call after
  // a frame-validation timeout — one-shot, cleared once consumed, so a
  // temporary mis-lock doesn't permanently blacklist a device that's
  // legitimately the only one around.
  String excludedAddress_;
  uint8_t assemblyBuffer_[kAssemblyBufferSize] = {};
  size_t assemblyLength_ = 0;
  BatteryTelemetry latest_;
  BmsBleStatus status_;
  void* client_ = nullptr;  // NimBLEClient*, kept opaque to this header
};

}  // namespace jkbmsr
