// The interval-boundary test that replaces "now % interval == 0".
//
// The old form is true for one second per interval. The cases below are the ones
// that matter: a loop that looks late must still fire, and looking twice inside
// the same interval must fire only once.

#include <Arduino.h>
#include <unity.h>

#include "cloud/IntervalBucket.h"

using jkbmsr::crossedIntervalBoundary;
using jkbmsr::intervalBucket;

void test_every_second_of_an_interval_is_the_same_bucket() {
  const time_t fiveMinutes = 300;
  const time_t start = 1762829400 / fiveMinutes * fiveMinutes;  // a boundary
  TEST_ASSERT_EQUAL_INT(intervalBucket(start, fiveMinutes), intervalBucket(start + 1, fiveMinutes));
  TEST_ASSERT_EQUAL_INT(intervalBucket(start, fiveMinutes), intervalBucket(start + 299, fiveMinutes));
}

void test_the_bucket_changes_at_the_boundary_and_not_before() {
  const time_t fiveMinutes = 300;
  const time_t start = 1762829400 / fiveMinutes * fiveMinutes;
  TEST_ASSERT_FALSE(crossedIntervalBoundary(start + 299, fiveMinutes, intervalBucket(start, fiveMinutes)));
  TEST_ASSERT_TRUE(crossedIntervalBoundary(start + 300, fiveMinutes, intervalBucket(start, fiveMinutes)));
}

void test_a_late_loop_still_fires_once() {
  // The defect this fixes: a six-second upload straddled the boundary, so the
  // one-second window was missed entirely. A bucket crossed ten seconds late
  // still counts, because the interval has changed.
  const time_t fiveMinutes = 300;
  const time_t start = 1762829400 / fiveMinutes * fiveMinutes;
  const time_t lastBucket = intervalBucket(start, fiveMinutes);
  TEST_ASSERT_TRUE(crossedIntervalBoundary(start + 310, fiveMinutes, lastBucket));
  // ... and having fired, the same bucket does not fire again.
  TEST_ASSERT_FALSE(crossedIntervalBoundary(start + 311, fiveMinutes, intervalBucket(start + 310, fiveMinutes)));
}

void test_a_missed_interval_does_not_double_send() {
  // Blocked for two intervals: one upload, not two.
  const time_t hour = 3600;
  const time_t start = 1762829400 / hour * hour;
  const time_t lastBucket = intervalBucket(start, hour);
  TEST_ASSERT_TRUE(crossedIntervalBoundary(start + 2 * hour + 5, hour, lastBucket));
}

void test_a_zero_interval_never_fires() {
  TEST_ASSERT_FALSE(crossedIntervalBoundary(1762829400, 0, 0));
}

void setup() {
  UNITY_BEGIN();
  RUN_TEST(test_every_second_of_an_interval_is_the_same_bucket);
  RUN_TEST(test_the_bucket_changes_at_the_boundary_and_not_before);
  RUN_TEST(test_a_late_loop_still_fires_once);
  RUN_TEST(test_a_missed_interval_does_not_double_send);
  RUN_TEST(test_a_zero_interval_never_fires);
  UNITY_END();
}

void loop() {}
