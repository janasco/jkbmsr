#pragma once

#include <Arduino.h>

namespace jkbmsr {

// Watches the BOOT button (GPIO0, active-low) for a long-press that requests
// re-provisioning without a reflash:
//   ~5s  → soft: clear Wi-Fi creds + JWT, keep device ID / claim code / secret
//   ~10s → factory: also clear the device secret (forces re-registration)
// Debounced; sample early in setup() and continuously from loop().
class ResetTrigger {
 public:
  static constexpr uint8_t kDefaultPin = 0;  // ESP32 BOOT
  static constexpr uint32_t kSoftHoldMs = 5000;
  static constexpr uint32_t kFactoryHoldMs = 10000;
  static constexpr uint32_t kDebounceMs = 50;

  void begin(uint8_t pin = kDefaultPin);

  // Sample the pin and update sticky request flags. Safe to call often.
  void poll();

  // Sticky until clear(). Soft and factory both imply a provisioning request.
  bool provisioningRequested() const { return softRequested_ || factoryRequested_; }
  bool factoryResetRequested() const { return factoryRequested_; }

  void clear();

 private:
  uint8_t pin_ = kDefaultPin;
  bool pressed_ = false;
  bool debounceSample_ = false;
  uint32_t debounceMs_ = 0;
  uint32_t pressStartMs_ = 0;
  bool softRequested_ = false;
  bool factoryRequested_ = false;
};

}  // namespace jkbmsr
