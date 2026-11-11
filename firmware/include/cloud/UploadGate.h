#pragma once

namespace jkbmsr {

/// Inputs to the telemetry upload decision, made pure so it can be tested on
/// the host. The loop cannot be.
struct UploadGate {
  /// The interval boundary has arrived (wall-clock aligned).
  bool due;
  /// `poll()` produced a fresh sample worth sending.
  bool haveSample;
  /// The low-cadence "still alive, BMS link down" heartbeat is due.
  bool heartbeatDue;
  /// A BMS link has come up since the last successful report.
  bool firstAfterLinkUp;
};

/// Should this loop iteration upload?
///
/// The boundary rule is unchanged: at the interval, upload a sample, or a
/// heartbeat if there is none. The addition is the first report after a BMS link
/// comes up: on the free tier the boundary is up to an hour away, and until the
/// first upload the dashboard has no `last_seen_at` at all, so a freshly booted
/// gateway reads as offline while it is polling every 60 seconds.
///
/// With no sample, only the boundary may send, so a link that is up but has not
/// produced a frame cannot cause a report on every loop iteration.
inline bool shouldUploadNow(const UploadGate& gate) {
  if (!gate.due && !gate.firstAfterLinkUp) {
    return false;
  }
  if (gate.haveSample) {
    return true;
  }
  return gate.due && gate.heartbeatDue;
}

}  // namespace jkbmsr
