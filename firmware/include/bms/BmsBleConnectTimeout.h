#pragma once

#include <stdint.h>

// How long to wait for a BLE link, in real seconds. This is split from the
// value handed to NimBLE because NimBLE-Arduino changed the UNIT of
// setConnectTimeout() between major versions:
//
//   NimBLE-Arduino 1.x: setConnectTimeout(uint8_t  seconds)       -> stores time * 1000 ms
//   NimBLE-Arduino 2.x: setConnectTimeout(uint32_t milliseconds)  -> stores time
//
// This firmware supports both: the older targets (env:dev, esp32-classic-*,
// esp32-s3-4mb, ...) pin 1.4.3, while env:esp32-s3-16mb and env:esp32-c6-4mb
// pin 2.x. A bare `setConnectTimeout(5)` -- the original idiom -- therefore
// means 5 seconds on the 1.x targets but 5 MILLISECONDS on the 2.x targets.
// 5 ms is shorter than a single BLE connection interval (>= 7.5 ms), so connect()
// timed out on every attempt on the exact stack the N16R8 field hardware runs
// (arduino-esp32 3.2.0 / IDF 5.4.1 / NimBLE-Arduino 2.5.1). Symptom observed in
// the field: the JK-BMS is discovered, then the BLE connect fails, forever.
//
// The BLE clients must therefore express the timeout in seconds and convert for
// the active NimBLE major version. bmsBleConnectTimeoutArg() is kept free of any
// NimBLE dependency so the conversion is a pure, host-testable function.
//
// NOTE: <NimBLEDevice.h> is included OUTSIDE the namespace on purpose. Including
// it inside drags NimBLE's own `std::list`/`std::vector` uses into `jkbmsr::std`,
// which does not exist, and fails to compile on the 1.x targets (env:dev and the
// esp32-classic/esp32-s3-4mb targets that `release.sh` compiles).
#if defined(__has_include)
#if __has_include(<NimBLEDevice.h>)
#include <NimBLEDevice.h>
#define JKBMSR_BMS_BLE_HAVE_NIMBLE 1
#endif
#endif

namespace jkbmsr {

constexpr uint32_t kBmsBleConnectTimeoutSeconds = 5;

// The argument NimBLE-Arduino's setConnectTimeout() expects.
constexpr uint32_t bmsBleConnectTimeoutArg(bool apiUsesMilliseconds) {
  return apiUsesMilliseconds ? kBmsBleConnectTimeoutSeconds * 1000U
                             : kBmsBleConnectTimeoutSeconds;
}

#if defined(JKBMSR_BMS_BLE_HAVE_NIMBLE)
// NimBLE-Arduino defines NIMBLE_CPP_VERSION_MAJOR from 2.x on; 1.x does not
// define it at all, which is why the check is `defined(...) && >= 2`.
#if defined(NIMBLE_CPP_VERSION_MAJOR) && (NIMBLE_CPP_VERSION_MAJOR >= 2)
constexpr bool kBmsBleNimbleTimeoutUsesMilliseconds = true;
#else
constexpr bool kBmsBleNimbleTimeoutUsesMilliseconds = false;
#endif

// Configure a freshly created NimBLE client with the correct-unit connect
// timeout. Call this instead of setConnectTimeout() directly so the version
// difference can never be missed again.
inline void applyBmsBleConnectTimeout(NimBLEClient* client) {
  client->setConnectTimeout(
      bmsBleConnectTimeoutArg(kBmsBleNimbleTimeoutUsesMilliseconds));
}
#endif

}  // namespace jkbmsr
