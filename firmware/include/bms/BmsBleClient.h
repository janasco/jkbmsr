#pragma once

#include <Arduino.h>
#include "BatteryTelemetry.h"

namespace jkbmsr {

constexpr uint8_t kMaxBmsBleCandidates = 5;

struct BmsBleCandidate {
  String address;
  String name;
  int rssi = -128;
  uint8_t addressType = 0;
};

// Shared shape for every vendor's BLE client (JkBmsBleClient,
// DalyBmsBleClient, JbdBmsBleClient) so main.cpp can dispatch on
// config.bmsVendor through one interface, mirroring BmsUartClient.h.
struct BmsBleStatus {
  bool enabled = false;
  bool connected = false;
  String state = "disabled";
  String address;
  String advertisedName;
  int rssi = -128;
  uint8_t addressType = 0;
  String lastError;
  uint32_t lastScanAtMs = 0;
  uint32_t lastConnectedAtMs = 0;
  BmsBleCandidate candidates[kMaxBmsBleCandidates];
  uint8_t candidateCount = 0;
  uint32_t lastFrameAtMs = 0;
  uint32_t framesDecoded = 0;
  uint32_t checksumErrors = 0;
  String hardwareVersion;
  String softwareVersion;
  bool is32s = false;
};

class BmsBleClient {
 public:
  virtual ~BmsBleClient() = default;
  // An empty address enables auto-discovery of the strongest nearby unit.
  virtual void begin(const String& address) = 0;
  virtual void stop() = 0;
  // Drives scanning/connection state; call every main-loop iteration.
  virtual void loop() = 0;
  // Returns the freshest decoded sample, if recent enough, and requests
  // the next one.
  virtual bool poll(BatteryTelemetry& telemetry) = 0;
  virtual BmsBleStatus status() const = 0;
};

}  // namespace jkbmsr
