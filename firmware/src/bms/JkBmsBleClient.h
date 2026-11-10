#pragma once

#include <Arduino.h>
#include "bms/Jk02FrameAssembler.h"

#include "BatteryTelemetry.h"
#include "bms/BmsBleClient.h"
#include "bms/BmsRequestBackoff.h"
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
//
// Every 0x96 the hardware accepts is an audible beep, so the two retry loops
// that can re-send it are bounded by a BmsRequestBackoff (doubling, capped):
// the stream re-request and the reconnect attempt. A brief stall still
// recovers on the base delay; a dead link widens instead of beeping forever.
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
  // Reconnect: first retry after the base delay, doubling per consecutive
  // failed attempt, capped at 60 s. The cap used to be 300 s, and a field log
  // from 2026-11-10 showed why that is too long: a marginal link (-92 dBm)
  // dropped, connections kept half-succeeding, and the backoff climbed to the
  // cap on the strength of failures that were not really failures -- so one
  // dropout cost five minutes of no telemetry, repeated. At 60 s the worst case
  // is one missed upload per drop, and the beep cost is at most one connect per
  // minute, which is the telemetry cadence anyway.
  //
  // Reset on a successful connection AND on every valid frame: a link that
  // delivers anything is alive, and the next drop deserves the fast path again.
  static constexpr uint32_t kReconnectBaseDelayMs = 30000;
  static constexpr uint32_t kReconnectMaxDelayMs = 60000;
  // A session that is connected but has produced no valid frame for this long is
  // treated as dead and dropped. The stale-stream re-request has already run at
  // 5 s; this is the escalation that used to not exist, so a half-open link
  // could hold the gateway silent indefinitely while it kept heartbeating.
  static constexpr uint32_t kSessionSilentDropMs = 30000;
  // JK-BMS auto-streams cell info at ~1-2 frames per second; a gap this long
  // means the stream has stalled and a re-request (with its beep) is due. The
  // re-request then backs off from this base, doubling to kStreamRequestMaxDelayMs.
  static constexpr uint32_t kStreamStaleMs = 5000;
  static constexpr uint32_t kStreamRequestBaseDelayMs = 5000;
  static constexpr uint32_t kStreamRequestMaxDelayMs = 120000;
  static constexpr uint32_t kSampleFreshMs = 65000;

  void connectIfDue();
  // Records an unanswered connect attempt and schedules the next one after the
  // current backoff delay. Returns that delay, in milliseconds, for the log.
  uint32_t scheduleNextConnect();
  bool discoverTarget();
  bool sendReadOnlyCommand(JkBmsReadOnlyCommand command);
  void processFrame(const uint8_t* frame, size_t length);
  // Emits a bounded, rate-limited raw-frame capture line when a frame is
  // dropped or fails to verify/decode, so the frame can be captured from the
  // board's own serial. Rate-limiting lives in Jk02RawCaptureGate.
  void logRawFrameCapture(const uint8_t* frame, size_t length, const String& reason);

  bool enabled_ = false;
  bool stackInitialized_ = false;
  String configuredAddress_;
  String targetAddress_;
  uint8_t targetAddressType_ = 0;
  uint32_t lastCommandMs_ = 0;
  // Next time a connect attempt may run; 0 makes the first attempt immediate.
  uint32_t nextConnectAttemptAtMs_ = 0;
  // Next time a stalled stream may be re-requested; 0 makes it immediate.
  uint32_t nextStreamRequestAtMs_ = 0;
  BmsRequestBackoff reconnectBackoff_{kReconnectBaseDelayMs, kReconnectMaxDelayMs};
  BmsRequestBackoff streamRequestBackoff_{kStreamRequestBaseDelayMs,
                                          kStreamRequestMaxDelayMs};
  bool deviceInfoReceived_ = false;
  Jk02DeviceInfo deviceInfo_;
  // Reassembles frames over the byte stream, not over notification boundaries:
  // a real JK-PB1A16S15P prefixes its frames with "AT\r\nAT\r\n".
  Jk02FrameAssembler assembler_;
  BatteryTelemetry latest_;
  BmsBleStatus status_;
  Jk02RawCaptureGate rawCaptureGate_;
  void* client_ = nullptr;  // NimBLEClient*, kept opaque to this header
};

}  // namespace jkbmsr
