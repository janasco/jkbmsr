// When to give up on a "connected" BLE link.
//
// The failure this guards against is not a dropped connection — the stack
// reports those. It is a link that stays up, never delivers another frame, and
// leaves the gateway heartbeating "BMS link down" indefinitely. The field log of
// 2026-11-10 shows exactly that for an hour.

#include <Arduino.h>
#include <unity.h>

#include "bms/BmsLinkLiveness.h"

using jkbmsr::BmsLinkLiveness;

void test_a_healthy_link_is_never_dropped() {
  constexpr uint32_t now = 100000;
  TEST_ASSERT_FALSE(BmsLinkLiveness::shouldDrop(now, now - 1000, true));
  TEST_ASSERT_FALSE(BmsLinkLiveness::shouldDrop(now, now - (BmsLinkLiveness::kSilentDropMs - 1), true));
}

void test_a_link_silent_past_the_threshold_is_dropped() {
  constexpr uint32_t now = 100000;
  TEST_ASSERT_TRUE(BmsLinkLiveness::shouldDrop(now, now - BmsLinkLiveness::kSilentDropMs, true));
  TEST_ASSERT_TRUE(BmsLinkLiveness::shouldDrop(now, now - 60000, true));
}

void test_a_disconnected_link_is_left_to_the_reconnect_path() {
  // Dropping here would race connectIfDue(); the link is already down.
  TEST_ASSERT_FALSE(BmsLinkLiveness::shouldDrop(100000, 1000, false));
}

void test_no_frame_yet_does_not_count_as_silence() {
  // Before the first frame there is nothing to be late; identification gates it.
  TEST_ASSERT_FALSE(BmsLinkLiveness::shouldDrop(100000, 0, true));
}

void test_the_comparison_survives_millis_wraparound() {
  // millis() wraps at ~49 days. Unsigned subtraction is what makes that safe:
  // a signed comparison here would drop a healthy link once per wrap, and hold a
  // dead one. lastFrame is just before the wrap, so elapsed = now + 256ms.
  const uint32_t lastFrame = 0xFFFFFF00;  // 256 ms before the wrap
  TEST_ASSERT_FALSE(BmsLinkLiveness::shouldDrop(1000, lastFrame, true));  // 1256 ms
  TEST_ASSERT_TRUE(BmsLinkLiveness::shouldDrop(40000, lastFrame, true));  // 40256 ms
}

void setup() {
  UNITY_BEGIN();
  RUN_TEST(test_a_healthy_link_is_never_dropped);
  RUN_TEST(test_a_link_silent_past_the_threshold_is_dropped);
  RUN_TEST(test_a_disconnected_link_is_left_to_the_reconnect_path);
  RUN_TEST(test_no_frame_yet_does_not_count_as_silence);
  RUN_TEST(test_the_comparison_survives_millis_wraparound);
  UNITY_END();
}

void loop() {}
