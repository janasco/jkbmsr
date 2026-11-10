#pragma once

#include <cstdint>

namespace jkbmsr {

/// Decides when a BLE session that is still "connected" has to be dropped.
///
/// Why this exists as its own header: the field log of 2026-11-10 shows a
/// gateway that connected, identified the pack, and then received nothing for an
/// hour while it kept heartbeating "BMS link down". The stale-stream re-request
/// ran, but nothing ever escalated, so the client stayed attached to a half-open
/// link and the dashboard stayed empty. The decision is pure so it can be tested
/// on the host, where the radio cannot.
///
/// A session is dead when it has produced no valid frame for [kSilentDropMs].
/// Callers must only ask while the link is up and the device has been identified:
/// before identification there is no stream to be missing.
class BmsLinkLiveness {
 public:
  static constexpr uint32_t kSilentDropMs = 30000;

  static bool shouldDrop(uint32_t nowMs, uint32_t lastFrameAtMs, bool connected) {
    if (!connected) {
      return false;
    }
    // lastFrameAtMs == 0 means "no frame yet"; the caller gates that with
    // identification, so treat it as never having been alive and do not drop on
    // the first tick.
    if (lastFrameAtMs == 0) {
      return false;
    }
    return static_cast<uint32_t>(nowMs - lastFrameAtMs) >= kSilentDropMs;
  }
};

}  // namespace jkbmsr
