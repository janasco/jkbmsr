#pragma once

#include <cstdint>

namespace jkbmsr {

// Timings for the remote-Wi-Fi connect/retry/restart behaviour: try for about
// three minutes across several attempts, then restart and try again, rather
// than sitting permanently in setup/AP mode. Named here (and overridden from
// AppConfig.h in main.cpp) so the policy is one readable object, not scattered
// millisecond literals.
struct WifiRetryTimings {
  // Explicit constructors (rather than relying on brace/aggregate init): the
  // ESP32 Arduino core here builds with an older C++ standard where a struct
  // with default member initializers is not an aggregate, so `WifiRetryTimings
  // {a, b}` would not compile. Host builds (-std=c++17) accept these the same.
  WifiRetryTimings() = default;
  WifiRetryTimings(uint32_t connectWindow, uint32_t retryDelay)
      : connectWindowMs(connectWindow), retryDelayMs(retryDelay) {}

  uint32_t connectWindowMs = 180000;  // ~3 minutes of attempts per boot
  uint32_t retryDelayMs = 5000;       // pause between attempts
};

// Pure decision logic for one connect window. Deliberately free of any Arduino
// or WiFi dependency so it compiles and runs natively (test/test_wifi_retry,
// driven by scripts/run-host-tests.sh). main.cpp owns the blocking connect()
// call and the restart; this class only answers "is an attempt due?" and "has
// the window expired?".
class WifiRetryPolicy {
 public:
  explicit WifiRetryPolicy(WifiRetryTimings timings = WifiRetryTimings()) : timings_(timings) {}

  // Begin a fresh window at nowMs. The first attempt is due immediately, so a
  // healthy network connects on the first try with no artificial delay.
  void beginWindow(uint32_t nowMs) {
    windowStartMs_ = nowMs;
    nextAttemptAtMs_ = nowMs;
    attempts_ = 0;
  }

  // True once connectWindowMs has elapsed since beginWindow(). Unsigned
  // subtraction so a millis() wrap does not corrupt the comparison.
  bool windowExpired(uint32_t nowMs) const {
    return static_cast<uint32_t>(nowMs - windowStartMs_) >= timings_.connectWindowMs;
  }

  // True when the next attempt is due. Signed comparison so a wrap is handled
  // the same way as the Arduino core's own elapsed-time idiom.
  bool attemptDue(uint32_t nowMs) const {
    return static_cast<int32_t>(nowMs - nextAttemptAtMs_) >= 0;
  }

  // Record that an attempt just ran (regardless of success) and schedule the
  // next one retryDelayMs later.
  void noteAttempt(uint32_t nowMs) {
    ++attempts_;
    nextAttemptAtMs_ = nowMs + timings_.retryDelayMs;
  }

  int attempts() const { return attempts_; }

 private:
  WifiRetryTimings timings_;
  uint32_t windowStartMs_ = 0;
  uint32_t nextAttemptAtMs_ = 0;
  int attempts_ = 0;
};

}  // namespace jkbmsr
