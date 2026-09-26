#pragma once

#include <Arduino.h>
#include "BatteryTelemetry.h"

namespace jkbmsr {

class TelemetryClient {
 public:
  explicit TelemetryClient(String apiBaseUrl);
  bool upload(const String& token, const BatteryTelemetry& telemetry);

  // True when the most recent request was rejected as unauthenticated (401).
  // The caller uses this to force a fresh device login — the token may have
  // been invalidated server-side (e.g. a signing-secret rotation), and the
  // firmware otherwise keeps presenting the dead token forever.
  bool authRejected() const { return authRejected_; }

 private:
  // Bounded so a long outage can't grow unbounded RAM use — this smooths
  // over transient blips (seconds to a couple minutes), not extended
  // downtime. Each slot holds a serialized JSON payload (up to 4KB, see
  // upload()'s size check), so the worst case is ~20KB, well within an
  // ESP32's RAM budget.
  static constexpr uint8_t kMaxPendingPayloads = 5;

  String apiBaseUrl_;
  String pendingPayloads_[kMaxPendingPayloads];
  uint8_t pendingCount_ = 0;
  bool authRejected_ = false;

  bool sendPayload(const String& token, const String& payload);
  void enqueuePending(const String& payload);
  // Attempts to send the oldest backlogged payload, at most one per call —
  // naturally rate-limits retries to one extra request per telemetry cycle
  // instead of bursting the whole backlog at once when connectivity returns.
  void flushOnePending(const String& token);
};

}  // namespace jkbmsr
