#pragma once

#include <Arduino.h>

#include "BatteryTelemetry.h"
#include "bms/BmsBleClient.h"

namespace jkbmsr {

// BLE client for JBD (Jiabaida) BMS packs (service 0xFF00, notify
// characteristic 0xFF01, write/control characteristic 0xFF02 — the
// defaults most units use; a minority of rebrand SKUs configure different
// UUIDs, not handled here). The frame format is byte-identical to
// JbdBmsParser's UART protocol, so no new decoder exists — this transport
// reassembles notification chunks into a complete frame and hands it
// straight to JbdBmsParser::parseFrame(). Explicitly not implemented: the
// password-authentication sub-protocol a small minority of JBD BLE units
// require before they'll answer telemetry requests. Disabled unless
// begin() is called with a target address; all radio work happens in
// loop().
//
// Note: these are the SAME UUIDs SeplosBmsBleClient uses — if both a JBD
// and a Seplos unit are advertising nearby, address-less auto-discovery
// can pick the wrong one. Configure an explicit bmsBleAddress when both
// vendors might be present. As a second line of defense, a connection that
// never produces a valid frame within kFrameValidationTimeoutMs is treated
// as a wrong-device lock and retried against the next candidate — see
// loop().
class JbdBmsBleClient : public BmsBleClient {
 public:
  // An empty address enables auto-discovery of the strongest nearby unit
  // advertising service UUID 0xFF00 (JBD units have no consistent
  // advertised-name prefix the way JK's "JK"/Daly's "DL" do).
  void begin(const String& address) override;
  void stop() override;
  void loop() override;
  bool poll(BatteryTelemetry& telemetry) override;
  BmsBleStatus status() const override;

  // Called from the NimBLE notification callback; reassembles chunked
  // notifications into a complete frame.
  void handleNotification(const uint8_t* data, size_t length);

 private:
  static constexpr uint32_t kReconnectIntervalMs = 30000;
  static constexpr uint32_t kSampleFreshMs = 65000;
  static constexpr uint32_t kRequestIntervalMs = 5000;
  // Cell-info frame for 32 cells is 4 + 64 + 3 = 71 bytes; hardware-info is
  // fixed at ~34 bytes. Generous headroom for both, matching JbdBmsParser.
  static constexpr size_t kAssemblyBufferSize = 128;
  // See the class comment above re: the shared-UUID collision with Seplos.
  static constexpr uint32_t kFrameValidationTimeoutMs = 20000;

  void connectIfDue();
  bool discoverTarget();
  bool sendReadCommand(uint8_t address);
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
