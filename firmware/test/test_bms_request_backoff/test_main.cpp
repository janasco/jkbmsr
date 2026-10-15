#include <Arduino.h>
#include <unity.h>

#include "bms/BmsRequestBackoff.h"

using namespace jkbmsr;

// BmsRequestBackoff bounds the two firmware retry loops that can re-send the
// JK-BMS 0x96 request, which beeps audibly on every frame the hardware accepts:
// the stalled-stream re-request (base 5 s, cap 120 s) and the reconnect attempt
// (base 30 s, cap 300 s). Without the backoff a dead link beeped at a fixed
// cadence forever. These assertions pin the contract the client relies on.

// Stream re-request timings, matching JkBmsBleClient's constants.
constexpr uint32_t kStreamBase = 5000;
constexpr uint32_t kStreamCap = 120000;

void test_no_failures_means_no_earned_wait(void) {
  BmsRequestBackoff backoff(kStreamBase, kStreamCap);
  TEST_ASSERT_EQUAL_UINT32(0, backoff.delayForFailures(0));
  TEST_ASSERT_EQUAL_UINT32(0, backoff.nextDelayMs());
  TEST_ASSERT_EQUAL_UINT32(0, backoff.failures());
}

void test_base_case_is_the_configured_base(void) {
  BmsRequestBackoff backoff(kStreamBase, kStreamCap);
  // The first unanswered attempt earns exactly one base delay.
  TEST_ASSERT_EQUAL_UINT32(kStreamBase, backoff.delayForFailures(1));
}

void test_delay_doubles_per_consecutive_failure(void) {
  BmsRequestBackoff backoff(kStreamBase, kStreamCap);
  TEST_ASSERT_EQUAL_UINT32(5000, backoff.delayForFailures(1));
  TEST_ASSERT_EQUAL_UINT32(10000, backoff.delayForFailures(2));
  TEST_ASSERT_EQUAL_UINT32(20000, backoff.delayForFailures(3));
  TEST_ASSERT_EQUAL_UINT32(40000, backoff.delayForFailures(4));
  TEST_ASSERT_EQUAL_UINT32(80000, backoff.delayForFailures(5));
}

void test_single_failure_does_not_jump_to_the_cap(void) {
  BmsRequestBackoff backoff(kStreamBase, kStreamCap);
  backoff.noteFailure();
  TEST_ASSERT_EQUAL_UINT32(1, backoff.failures());
  TEST_ASSERT_EQUAL_UINT32(kStreamBase, backoff.nextDelayMs());
  TEST_ASSERT_TRUE(backoff.nextDelayMs() < kStreamCap);
}

void test_cap_is_never_exceeded_and_holds(void) {
  BmsRequestBackoff backoff(kStreamBase, kStreamCap);
  // 5 s doubling reaches the 120 s cap at the sixth failure (32 * 5 s = 160 s,
  // clamped) and stays there no matter how many more attempts fail.
  TEST_ASSERT_EQUAL_UINT32(kStreamCap, backoff.delayForFailures(6));
  TEST_ASSERT_EQUAL_UINT32(kStreamCap, backoff.delayForFailures(7));
  TEST_ASSERT_EQUAL_UINT32(kStreamCap, backoff.delayForFailures(100));
}

void test_reset_on_success_restores_the_fast_path(void) {
  BmsRequestBackoff backoff(kStreamBase, kStreamCap);
  for (int i = 0; i < 6; ++i) {
    backoff.noteFailure();
  }
  TEST_ASSERT_EQUAL_UINT32(kStreamCap, backoff.nextDelayMs());

  backoff.reset();
  TEST_ASSERT_EQUAL_UINT32(0, backoff.failures());
  // A frame arrived: the very next failure starts from the base again.
  backoff.noteFailure();
  TEST_ASSERT_EQUAL_UINT32(kStreamBase, backoff.nextDelayMs());
}

// noteFailure() is what the client calls after each send; nextDelayMs() must
// walk the sequence the client schedules against.
void test_note_failure_advances_the_sequence(void) {
  BmsRequestBackoff backoff(kStreamBase, kStreamCap);
  const uint32_t expected[] = {5000, 10000, 20000, 40000, 80000, 120000, 120000};
  for (uint32_t i = 0; i < sizeof(expected) / sizeof(expected[0]); ++i) {
    backoff.noteFailure();
    TEST_ASSERT_EQUAL_UINT32(expected[i], backoff.nextDelayMs());
  }
}

// The reconnect policy is a second instance with different timings; the helper
// must not bake in the stream values.
void test_reconnect_timings_are_independent(void) {
  BmsRequestBackoff reconnect(30000, 300000);
  TEST_ASSERT_EQUAL_UINT32(30000, reconnect.delayForFailures(1));
  TEST_ASSERT_EQUAL_UINT32(60000, reconnect.delayForFailures(2));
  TEST_ASSERT_EQUAL_UINT32(120000, reconnect.delayForFailures(3));
  TEST_ASSERT_EQUAL_UINT32(240000, reconnect.delayForFailures(4));
  TEST_ASSERT_EQUAL_UINT32(300000, reconnect.delayForFailures(5));
  TEST_ASSERT_EQUAL_UINT32(300000, reconnect.delayForFailures(50));
}

// Nothing may ever make the delay shrink as failures accumulate, and it must
// never wrap past the cap on the way.
void test_sequence_is_monotonic_and_bounded(void) {
  BmsRequestBackoff backoff(kStreamBase, kStreamCap);
  uint32_t previous = 0;
  for (uint32_t failures = 0; failures <= 40; ++failures) {
    const uint32_t delay = backoff.delayForFailures(failures);
    TEST_ASSERT_TRUE(delay >= previous);
    TEST_ASSERT_TRUE(delay <= kStreamCap);
    previous = delay;
  }
}

void setup() {
  UNITY_BEGIN();
  RUN_TEST(test_no_failures_means_no_earned_wait);
  RUN_TEST(test_base_case_is_the_configured_base);
  RUN_TEST(test_delay_doubles_per_consecutive_failure);
  RUN_TEST(test_single_failure_does_not_jump_to_the_cap);
  RUN_TEST(test_cap_is_never_exceeded_and_holds);
  RUN_TEST(test_reset_on_success_restores_the_fast_path);
  RUN_TEST(test_note_failure_advances_the_sequence);
  RUN_TEST(test_reconnect_timings_are_independent);
  RUN_TEST(test_sequence_is_monotonic_and_bounded);
  UNITY_END();
}

void loop() {}
