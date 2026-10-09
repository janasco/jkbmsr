#include <Arduino.h>
#include <unity.h>

#include "network/WifiRetryPolicy.h"

using jkbmsr::WifiRetryPolicy;
using jkbmsr::WifiRetryTimings;

// The remote-Wi-Fi connect/retry/restart timing. These assertions pin the
// boundaries the owner asked for: a first attempt immediately, retries gated
// by the retry delay, and a window that closes after ~3 minutes so main.cpp
// restarts and tries again rather than sitting in setup forever.

void test_first_attempt_is_immediate(void) {
  WifiRetryPolicy policy;
  policy.beginWindow(1000);
  TEST_ASSERT_TRUE(policy.attemptDue(1000));
  TEST_ASSERT_FALSE(policy.windowExpired(1000));
}

void test_retry_delay_gates_next_attempt(void) {
  WifiRetryPolicy policy(WifiRetryTimings{180000, 5000});
  policy.beginWindow(0);
  policy.noteAttempt(0);
  TEST_ASSERT_FALSE(policy.attemptDue(4999));
  TEST_ASSERT_TRUE(policy.attemptDue(5000));
}

void test_window_expires_after_configured_time(void) {
  WifiRetryPolicy policy;
  policy.beginWindow(10000);
  TEST_ASSERT_FALSE(policy.windowExpired(10000 + 179999));
  TEST_ASSERT_TRUE(policy.windowExpired(10000 + 180000));
}

void test_attempt_counter_increments(void) {
  WifiRetryPolicy policy;
  policy.beginWindow(0);
  TEST_ASSERT_EQUAL_INT(0, policy.attempts());
  policy.noteAttempt(0);
  policy.noteAttempt(25000);
  TEST_ASSERT_EQUAL_INT(2, policy.attempts());
}

// A realistic boot: with a ~25s blocking connect per attempt and a 5s retry
// delay, a 3-minute window should fit several attempts (not one, and not
// zero). This is the property the "several tries" requirement rests on.
void test_realistic_boot_yields_several_attempts(void) {
  WifiRetryPolicy policy(WifiRetryTimings{180000, 5000});
  const uint32_t connectMs = 25000;
  uint32_t now = 0;
  policy.beginWindow(now);
  while (!policy.windowExpired(now)) {
    if (policy.attemptDue(now)) {
      policy.noteAttempt(now);
      now += connectMs;  // the blocking connect() call
    } else {
      now += 50;
    }
  }
  TEST_ASSERT_GREATER_OR_EQUAL_UINT32(5, static_cast<uint32_t>(policy.attempts()));
  TEST_ASSERT_GREATER_OR_EQUAL_UINT32(180000, now);
}

// millis() wraps every ~49 days; neither the window nor the retry gate may be
// fooled by it.
void test_wrap_around_is_handled(void) {
  WifiRetryPolicy policy(WifiRetryTimings{180000, 5000});
  const uint32_t start = 0xFFFF0000u;  // ~64s before the wrap
  policy.beginWindow(start);
  TEST_ASSERT_FALSE(policy.windowExpired(start + 60000));  // 60s in, still open
  TEST_ASSERT_TRUE(policy.windowExpired(start + 200000));  // past the window, across the wrap
  policy.noteAttempt(start + 60000);
  TEST_ASSERT_TRUE(policy.attemptDue(start + 65000));
}

void setup() {
  UNITY_BEGIN();
  RUN_TEST(test_first_attempt_is_immediate);
  RUN_TEST(test_retry_delay_gates_next_attempt);
  RUN_TEST(test_window_expires_after_configured_time);
  RUN_TEST(test_attempt_counter_increments);
  RUN_TEST(test_realistic_boot_yields_several_attempts);
  RUN_TEST(test_wrap_around_is_handled);
  UNITY_END();
}

void loop() {}
