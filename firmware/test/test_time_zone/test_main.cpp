// The validator that guards setenv("TZ").
//
// libc ignores a malformed TZ string without reporting anything, so a bad value
// would leave the device printing UTC while the settings page claimed a local
// zone. Refusing the value up front is the only way to notice, which makes this
// predicate load-bearing rather than cosmetic — hence the negative cases below.

#include <Arduino.h>
#include <unity.h>

#include "clock/SystemClock.h"

using jkbmsr::applyTimeZone;
using jkbmsr::currentTimeZone;
using jkbmsr::isValidPosixTimeZone;

void test_accepts_the_shapes_we_ship() {
  TEST_ASSERT_TRUE(isValidPosixTimeZone("UTC0"));
  TEST_ASSERT_TRUE(isValidPosixTimeZone("PST-8"));                       // UTC+8, no DST
  TEST_ASSERT_TRUE(isValidPosixTimeZone("<-08>8"));                      // quoted-name form
  TEST_ASSERT_TRUE(isValidPosixTimeZone("CET-1CEST,M3.5.0,M10.5.0/3"));  // EU DST rules
  TEST_ASSERT_TRUE(isValidPosixTimeZone("EST5EDT,M3.2.0,M11.1.0"));
}

void test_rejects_empty_and_overlong() {
  TEST_ASSERT_FALSE(isValidPosixTimeZone(""));
  // 62 characters, over the 48-character cap.
  TEST_ASSERT_FALSE(isValidPosixTimeZone(
      "ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"));
}

void test_rejects_characters_posix_cannot_hold() {
  // An IANA name is what a person types first; a space, a quote and a newline
  // are what copy-paste and JSON encoding leave behind. None can reach setenv.
  TEST_ASSERT_FALSE(isValidPosixTimeZone("Asia/Manila"));
  TEST_ASSERT_FALSE(isValidPosixTimeZone("UTC0 "));
  TEST_ASSERT_FALSE(isValidPosixTimeZone("\"UTC0\""));
  TEST_ASSERT_FALSE(isValidPosixTimeZone("UTC0;rm -rf /"));
  TEST_ASSERT_FALSE(isValidPosixTimeZone("UTC0\n"));
}

void test_apply_keeps_the_previous_zone_on_a_bad_value() {
  applyTimeZone("UTC0");
  TEST_ASSERT_EQUAL_STRING("UTC0", currentTimeZone().c_str());
  applyTimeZone("not a zone");
  TEST_ASSERT_EQUAL_STRING("UTC0", currentTimeZone().c_str());
  applyTimeZone("PST-8");
  TEST_ASSERT_EQUAL_STRING("PST-8", currentTimeZone().c_str());
  // A rejected value must not knock out the zone that was already applied.
  applyTimeZone("Asia/Manila");
  TEST_ASSERT_EQUAL_STRING("PST-8", currentTimeZone().c_str());
  applyTimeZone("UTC0");
}

void setup() {
  UNITY_BEGIN();
  RUN_TEST(test_accepts_the_shapes_we_ship);
  RUN_TEST(test_rejects_empty_and_overlong);
  RUN_TEST(test_rejects_characters_posix_cannot_hold);
  RUN_TEST(test_apply_keeps_the_previous_zone_on_a_bad_value);
  UNITY_END();
}

void loop() {}
