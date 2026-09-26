#include "DeviceIdentity.h"

#include <cstdio>

#include "HardwareProfile.h"

#if defined(ARDUINO_ARCH_ESP8266)
#include <ESP8266WiFi.h>
#else
#include <WiFi.h>
#include <esp_random.h>
#endif

namespace jkbmsr {

namespace {

uint32_t secureRandomWord() {
#if defined(ARDUINO_ARCH_ESP8266)
  // ESP8266's hardware RNG register is exposed through the Arduino core.
  return ESP.random();
#else
  return esp_random();
#endif
}

}  // namespace

String DeviceIdentity::generateDeviceId() const {
  uint8_t bytes[16];
  for (size_t index = 0; index < sizeof(bytes); index += 4) {
    const uint32_t word = secureRandomWord();
    bytes[index] = static_cast<uint8_t>(word >> 24);
    bytes[index + 1] = static_cast<uint8_t>(word >> 16);
    bytes[index + 2] = static_cast<uint8_t>(word >> 8);
    bytes[index + 3] = static_cast<uint8_t>(word);
  }

  String id = "jkbmsr-";
  for (uint8_t byteValue : bytes) {
    if (byteValue < 0x10) {
      id += "0";
    }
    id += String(byteValue, HEX);
  }
  return id;
}

String DeviceIdentity::generateClaimCode() const {
  // Crockford-style alphabet with the visually ambiguous 0/O/1/I/L removed so
  // the code is safe to read off a label. 32 symbols → 5 bits each.
  static const char kAlphabet[] = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  constexpr size_t kAlphabetSize = sizeof(kAlphabet) - 1;
  constexpr size_t kCodeLength = 8;

  String code;
  code.reserve(kCodeLength);
  for (size_t index = 0; index < kCodeLength; ++index) {
    code += kAlphabet[secureRandomWord() % kAlphabetSize];
  }
  return code;
}

String DeviceIdentity::hardwareId() const {
  // Backward-compatible descriptive field. The factory UID travels only in
  // hardwareFingerprint() and is HMACed by the API before database storage.
  return hardwarePlatform() + ":" + hardwareModel();
}

String DeviceIdentity::hardwareFingerprint() const {
#if defined(ARDUINO_ARCH_ESP8266)
  // ESP.getEfuseMac() (esp-idf, a 48-bit value) doesn't exist on this core;
  // ESP.getChipId() is its closest equivalent (32-bit, derived from the
  // chip's MAC address) — narrower, but still stable per-chip, which is all
  // this is used for.
  const uint32_t uid = ESP.getChipId();
  if (uid == 0) {
    return "unknown";
  }
  char encoded[32];
  snprintf(encoded, sizeof(encoded), "chipid-v1:%06lx", static_cast<unsigned long>(uid));
#else
  const uint64_t uid = ESP.getEfuseMac();
  if (uid == 0) {
    return "unknown";
  }
  char encoded[32];
  snprintf(encoded, sizeof(encoded), "efuse-v1:%012llx", static_cast<unsigned long long>(uid));
#endif
  return String(encoded);
}

String DeviceIdentity::hardwarePlatform() const {
  return kHardwarePlatform;
}

String DeviceIdentity::hardwareModel() const {
#if defined(ARDUINO_ARCH_ESP8266)
  return "ESP8266EX";
#else
  return ESP.getChipModel();
#endif
}

}  // namespace jkbmsr
