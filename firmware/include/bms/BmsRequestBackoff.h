#pragma once

#include <stdint.h>

namespace jkbmsr {

// Bounded exponential backoff for a request that has an audible side effect.
//
// The JK-BMS beeps on every 0x96 ("settings + telemetry stream") frame the
// hardware accepts, so any retry loop that re-sends 0x96 at a fixed cadence
// turns a stalled link into a metronome the owner can hear. This helper makes
// the wait between such retries grow instead: one base delay for the first
// unanswered attempt, doubling per consecutive failure, clamped at maxDelayMs.
// A single success -- a frame arrived, a connection came up -- resets it to the
// fast path, so a healthy link is never penalised for an unrelated stall.
//
// It is pure and header-only: a function of the failure count alone, no clock
// and no Arduino, so it is exercised natively by test/test_bms_request_backoff
// (driven by scripts/run-host-tests.sh). The caller owns the timestamps and
// asks for nextDelayMs() after noteFailure().
struct BmsRequestBackoff {
  constexpr BmsRequestBackoff(uint32_t baseDelayMs, uint32_t maxDelayMs)
      : baseDelayMs_(baseDelayMs), maxDelayMs_(maxDelayMs) {}

  // Milliseconds to wait before the next attempt, after `consecutiveFailures`
  // attempts have gone unanswered. Zero failures means no wait has been earned
  // yet (0). Each further failure doubles the base, clamped at maxDelayMs_. For
  // a 5 s base and a 120 s cap the sequence is 5, 10, 20, 40, 80, 120, 120, ...
  // -- those values are the DELAY before each next request, not cumulative
  // timestamps.
  uint32_t delayForFailures(uint32_t consecutiveFailures) const {
    if (consecutiveFailures == 0) {
      return 0;
    }
    uint32_t delay = baseDelayMs_;
    for (uint32_t i = 1; i < consecutiveFailures && delay < maxDelayMs_; ++i) {
      delay *= 2;
      if (delay > maxDelayMs_) {
        delay = maxDelayMs_;
      }
    }
    return delay;
  }

  // The wait owed before the next attempt, given the failures recorded so far.
  uint32_t nextDelayMs() const { return delayForFailures(failures_); }

  uint32_t failures() const { return failures_; }

  // Record an unanswered attempt: the next wait is one step longer.
  void noteFailure() {
    if (failures_ < kMaxTrackedFailures) {
      ++failures_;
    }
  }

  // A frame arrived / a connection came up: back to the fast path immediately.
  void reset() { failures_ = 0; }

 private:
  // Once the delay is capped, a larger count yields the same answer, and 32
  // doublings would overflow uint32_t. Clamping the counter here keeps
  // noteFailure() and the multiply loop safe without changing any returned
  // delay (maxDelayMs_ is far below 2^32).
  static constexpr uint32_t kMaxTrackedFailures = 32;

  uint32_t baseDelayMs_;
  uint32_t maxDelayMs_;
  uint32_t failures_ = 0;
};

}  // namespace jkbmsr
