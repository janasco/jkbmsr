#pragma once

#include <Arduino.h>

#include "BatteryTelemetry.h"
#include "bms/BmsBleClient.h"
#include "bms/Jk02Decoder.h"
#include "bms/JkBmsReadOnlyProtocol.h"

namespace jkbmsr {

// BLE client for JK-BMS packs (service 0xFFE0, characteristic 0xFFE1). Sends
// the 0x97 device-info command once per connection to auto-detect the frame
// layout from the hardware version, then a single 0x96 cell-info request to
// start the BMS's silent auto-stream; it reads from that stream afterwards and
// only re-requests when the stream stalls (kStreamStaleMs). Telemetry reads
// need no BMS app password. Disabled unless begin() is called with a target
// address; all radio work happens in loop().
class JkBmsBleClient : public BmsBleClient {
 public:
  // An empty address enables auto-discovery of the strongest nearby JK-BMS.
  void begin(const String& address) override;
  void stop() override;
  // Drives scanning/connection state; call every main-loop iteration.
  void loop() override;
  // Returns the freshest decoded auto-streamed cell-info sample, if younger
  // than kSampleFreshMs, re-requesting the 0x96 stream only when it stalls.
  bool poll(BatteryTelemetry& telemetry) override;
  BmsBleStatus status() const override;

  // Called from the NimBLE notification callback; assembles 20-byte
  // notifications into full 300-byte frames.
  void handleNotification(const uint8_t* data, size_t length);

 private:
  static constexpr uint32_t kReconnectIntervalMs = 30000;
  // JK-BMS auto-streams cell info at ~1-2 frames per second; a gap this long
  // means the stream has stalled and a re-request (with its beep) is due.
  static constexpr uint32_t kStreamStaleMs = 5000;
  static constexpr uint32_t kSampleFreshMs = 65000;
  static constexpr size_t kAssemblyBufferSize = 320;

  void connectIfDue();
  bool discoverTarget();
  bool sendReadOnlyCommand(JkBmsReadOnlyCommand command);
  void processFrame(const uint8_t* frame, size_t length);

  bool enabled_ = false;
  bool stackInitialized_ = false;
  String configuredAddress_;
  String targetAddress_;
  uint8_t targetAddressType_ = 0;
  uint32_t lastConnectAttemptMs_ = 0;
  uint32_t lastCommandMs_ = 0;
  bool deviceInfoReceived_ = false;
  Jk02DeviceInfo deviceInfo_;
  uint8_t assemblyBuffer_[kAssemblyBufferSize] = {};
  size_t assemblyLength_ = 0;
  BatteryTelemetry latest_;
  BmsBleStatus status_;
  void* client_ = nullptr;  // NimBLEClient*, kept opaque to this header
};

}  // namespace jkbmsr
