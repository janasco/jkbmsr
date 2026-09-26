#include "ResetTrigger.h"

namespace jkbmsr {

void ResetTrigger::begin(uint8_t pin) {
  pin_ = pin;
  pinMode(pin_, INPUT_PULLUP);
  const bool raw = digitalRead(pin_) == LOW;
  pressed_ = raw;
  debounceSample_ = raw;
  debounceMs_ = millis();
  pressStartMs_ = pressed_ ? millis() : 0;
  softRequested_ = false;
  factoryRequested_ = false;
}

void ResetTrigger::poll() {
  const bool raw = digitalRead(pin_) == LOW;
  const uint32_t now = millis();

  if (raw != debounceSample_) {
    debounceSample_ = raw;
    debounceMs_ = now;
  } else if (raw != pressed_ && (now - debounceMs_) >= kDebounceMs) {
    pressed_ = raw;
    if (pressed_) {
      pressStartMs_ = now;
    }
  }

  if (!pressed_) {
    return;
  }

  const uint32_t heldMs = now - pressStartMs_;
  if (heldMs >= kFactoryHoldMs) {
    factoryRequested_ = true;
    softRequested_ = true;
  } else if (heldMs >= kSoftHoldMs) {
    softRequested_ = true;
  }
}

void ResetTrigger::clear() {
  softRequested_ = false;
  factoryRequested_ = false;
}

}  // namespace jkbmsr
