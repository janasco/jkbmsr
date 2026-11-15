// The healthy-path guarantee: a working gateway is never restarted by the watchdog.

#include <Arduino.h>
#include <unity.h>
#include "cloud/HealthWatchdog.h"

using jkbmsr::HealthWatchdog;

namespace {
const uint32_t kMinute = 60UL * 1000UL;
}

void test_a_working_gateway_is_never_restarted() {
  HealthWatchdog watchdog;
  watchdog.noteWifi(true);
  for (uint32_t t = 0; t < 24 * 60 * kMinute; t += kMinute) {
    watchdog.noteContact(t);
    TEST_ASSERT_FALSE(watchdog.shouldRestart(t + kMinute / 2));
  }
}

void test_a_hung_stack_is_restarted_after_the_threshold() {
  HealthWatchdog watchdog;
  watchdog.noteWifi(true);
  watchdog.noteContact(0);
  TEST_ASSERT_FALSE(watchdog.shouldRestart(9 * kMinute));
  TEST_ASSERT_TRUE(watchdog.shouldRestart(11 * kMinute));
}

void test_no_restart_while_wifi_is_down() {
  HealthWatchdog watchdog;
  watchdog.noteWifi(false);
  watchdog.noteContact(0);
  TEST_ASSERT_FALSE(watchdog.shouldRestart(30 * kMinute));
}

void test_threshold_backs_off_after_each_restart() {
  HealthWatchdog watchdog;
  watchdog.noteWifi(true);
  watchdog.noteContact(0);
  TEST_ASSERT_TRUE(watchdog.shouldRestart(11 * kMinute));
  TEST_ASSERT_EQUAL_UINT32(20 * kMinute, watchdog.thresholdMs());
  // The next window is twenty minutes, not ten.
  TEST_ASSERT_FALSE(watchdog.shouldRestart(25 * kMinute));
  TEST_ASSERT_TRUE(watchdog.shouldRestart(32 * kMinute));
}

void test_contact_again_returns_to_the_fast_threshold() {
  HealthWatchdog watchdog;
  watchdog.noteWifi(true);
  watchdog.noteContact(0);
  TEST_ASSERT_TRUE(watchdog.shouldRestart(11 * kMinute));
  watchdog.noteContact(12 * kMinute);
  TEST_ASSERT_EQUAL_UINT8(0, watchdog.restarts());
}

void setup() {
  UNITY_BEGIN();
  RUN_TEST(test_a_working_gateway_is_never_restarted);
  RUN_TEST(test_a_hung_stack_is_restarted_after_the_threshold);
  RUN_TEST(test_no_restart_while_wifi_is_down);
  RUN_TEST(test_threshold_backs_off_after_each_restart);
  RUN_TEST(test_contact_again_returns_to_the_fast_threshold);
  UNITY_END();
}

void loop() {}
