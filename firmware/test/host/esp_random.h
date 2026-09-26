#pragma once
// Minimal esp_random host shim — NOT esp-idf's hardware RNG.
//
// Why: device/DeviceIdentity.cpp and provisioning/CaptivePortal.cpp both mint
// secrets from esp_random() (claim codes, device IDs, captive-portal session
// tokens). A host has no TRNG, so this substitutes a seeded std::mt19937 —
// genuinely random per process, not a fixed constant. It must NOT be constant:
// test/test_provisioning asserts that eight generateClaimCode() draws are not
// all identical, and a stubbed counter would either trivially pass that or,
// worse, hide a real "the RNG never advances" defect in the caller.
//
// This is a test scaffold only. It must never be on the include path for a real
// firmware build.

#include <cstdint>
#include <random>

inline uint32_t esp_random() {
  static thread_local std::mt19937 generator([] {
    std::random_device seed;
    return static_cast<uint32_t>(seed()) ^ (static_cast<uint32_t>(seed()) << 16);
  }());
  return generator();
}
