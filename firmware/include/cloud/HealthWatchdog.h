#pragma once

#include <Arduino.h>

namespace jkbmsr {

/// Restarts a gateway that has stopped talking to the cloud.
///
/// Deliberately not a timer. A board that is working does not need downtime, and a
/// board that is hung does not need it every five hours regardless of state. The
/// condition is "Wi-Fi is up and nothing has reached the cloud for long enough that
/// the network stack is the suspect", which is the failure a watchdog can actually
/// fix - and it is logged, so the next person has evidence rather than a pattern.
///
/// The threshold doubles on each restart, up to an hour. A single hung stack gets one
/// restart promptly; a board that keeps hanging does not become a five-hourly reboot
/// loop.
class HealthWatchdog {
 public:
  explicit HealthWatchdog(uint32_t thresholdMs = 10UL * 60UL * 1000UL,
                          uint32_t maxThresholdMs = 60UL * 60UL * 1000UL)
      : thresholdMs_(thresholdMs), maxThresholdMs_(maxThresholdMs) {}

  /// Called on every successful cloud exchange: a config fetch, a telemetry upload, a
  /// login. This is the proof the watchdog is waiting for.
  void noteContact(uint32_t nowMs) {
    lastContactMs_ = nowMs;
    started_ = true;
    restartsSinceContact_ = 0;
  }

  void noteWifi(bool connected) { wifiUp_ = connected; }

  /// True at most once per threshold: the caller restarts, and the next call backs off.
  bool shouldRestart(uint32_t nowMs) {
    if (!started_ || !wifiUp_) {
      return false;
    }
    if (nowMs - lastContactMs_ < thresholdMs_) {
      return false;
    }
    // Back off before returning, so a failed restart cannot trigger another
    // immediately on the next loop iteration.
    lastContactMs_ = nowMs;
    restartsSinceContact_ += 1;
    const uint32_t next = thresholdMs_ * 2;
    thresholdMs_ = next > maxThresholdMs_ ? maxThresholdMs_ : next;
    return true;
  }

  uint32_t thresholdMs() const { return thresholdMs_; }
  uint8_t restarts() const { return restartsSinceContact_; }

 private:
  uint32_t thresholdMs_;
  uint32_t maxThresholdMs_;
  uint32_t lastContactMs_ = 0;
  bool started_ = false;
  bool wifiUp_ = false;
  uint8_t restartsSinceContact_ = 0;
};

/// Records a successful cloud exchange. Defined in main.cpp, where the one watchdog
/// instance lives, so the clients do not need a reference to it.
void noteCloudContact(uint32_t nowMs);

}  // namespace jkbmsr
