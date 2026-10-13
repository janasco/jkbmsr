#include <Arduino.h>
#include <unity.h>

#include "bms/BmsBleConnectTimeout.h"

using namespace jkbmsr;

// NimBLE-Arduino changed the unit of setConnectTimeout() between major
// versions: 1.x takes SECONDS, 2.x takes MILLISECONDS. The BLE clients pass a
// value expressed in seconds and rely on bmsBleConnectTimeoutArg() to convert
// it, so this suite pins both sides of that conversion. Without it, a bare
// `5` reaches setConnectTimeout() unchanged and means 5 ms on the 2.x targets
// (esp32-s3-16mb, esp32-c6-4mb) -- shorter than one connection interval, so
// every BLE connect() fails.

void test_timeout_is_five_seconds(void) {
  TEST_ASSERT_EQUAL_UINT32(5, kBmsBleConnectTimeoutSeconds);
}

// NimBLE-Arduino 1.x: parameter is seconds, so it must be passed through.
void test_nimble_1x_argument_is_seconds(void) {
  TEST_ASSERT_EQUAL_UINT32(5, bmsBleConnectTimeoutArg(false));
}

// NimBLE-Arduino 2.x: parameter is milliseconds, so 5 s must arrive as 5000.
void test_nimble_2x_argument_is_milliseconds(void) {
  TEST_ASSERT_EQUAL_UINT32(5000, bmsBleConnectTimeoutArg(true));
}

// The bug being fixed is exactly this inequality: a 5 s timeout must never be
// handed to the millisecond API as a bare 5.
void test_millisecond_api_is_never_a_bare_five(void) {
  TEST_ASSERT_TRUE(bmsBleConnectTimeoutArg(true) != 5);
}

void setup() {
  UNITY_BEGIN();
  RUN_TEST(test_timeout_is_five_seconds);
  RUN_TEST(test_nimble_1x_argument_is_seconds);
  RUN_TEST(test_nimble_2x_argument_is_milliseconds);
  RUN_TEST(test_millisecond_api_is_never_a_bare_five);
  UNITY_END();
}

void loop() {}
