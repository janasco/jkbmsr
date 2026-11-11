// The telemetry upload decision.
//
// The failure this pins is the one that would be invisible in the field: a link
// that is up but has not delivered a frame yet must not upload on every loop
// iteration. Only a sample, or the boundary heartbeat, may send.

#include <Arduino.h>
#include <unity.h>

#include "cloud/UploadGate.h"

using jkbmsr::shouldUploadNow;
using jkbmsr::UploadGate;

void test_nothing_due_and_no_new_link_sends_nothing() {
  TEST_ASSERT_FALSE(shouldUploadNow({false, true, false, false}));
  TEST_ASSERT_FALSE(shouldUploadNow({false, false, false, false}));
}

void test_the_first_sample_after_a_link_up_sends_immediately() {
  // The point of the change: a fresh boot is visible in seconds, not at the
  // next hourly boundary.
  TEST_ASSERT_TRUE(shouldUploadNow({false, true, false, true}));
}

void test_a_link_up_with_no_frame_does_not_send_on_every_loop() {
  // Without this, firstAfterLinkUp alone would upload forever: the flag stays
  // true until a sample arrives.
  TEST_ASSERT_FALSE(shouldUploadNow({false, false, false, true}));
  TEST_ASSERT_FALSE(shouldUploadNow({false, false, true, true}));
}

void test_the_boundary_still_works() {
  TEST_ASSERT_TRUE(shouldUploadNow({true, true, false, false}));   // sample at the boundary
  TEST_ASSERT_TRUE(shouldUploadNow({true, false, true, false}));   // heartbeat at the boundary
  TEST_ASSERT_FALSE(shouldUploadNow({true, false, false, false})); // boundary, no data, no heartbeat yet
}

void setup() {
  UNITY_BEGIN();
  RUN_TEST(test_nothing_due_and_no_new_link_sends_nothing);
  RUN_TEST(test_the_first_sample_after_a_link_up_sends_immediately);
  RUN_TEST(test_a_link_up_with_no_frame_does_not_send_on_every_loop);
  RUN_TEST(test_the_boundary_still_works);
  UNITY_END();
}

void loop() {}
