#include <Arduino.h>
#include <unity.h>

#include "ota/VersionCompare.h"

using namespace jkbmsr;

void test_strictly_newer(void) {
  TEST_ASSERT_TRUE(isStrictlyNewer("0.1.4", "0.1.3"));
  TEST_ASSERT_TRUE(isStrictlyNewer("0.2.0", "0.1.9"));
  TEST_ASSERT_TRUE(isStrictlyNewer("1.0.0", "0.9.9"));
  TEST_ASSERT_TRUE(isStrictlyNewer("0.1.10", "0.1.9"));
}

void test_equal_or_older_blocked(void) {
  TEST_ASSERT_FALSE(isStrictlyNewer("0.1.3", "0.1.3")); // equal
  TEST_ASSERT_FALSE(isStrictlyNewer("0.1.2", "0.1.3")); // rollback
  TEST_ASSERT_FALSE(isStrictlyNewer("0.0.9", "0.1.0"));
  TEST_ASSERT_FALSE(isStrictlyNewer("0.1.9", "0.1.10"));
}

void test_prerelease_ordering(void) {
  TEST_ASSERT_TRUE(isStrictlyNewer("0.2.0", "0.2.0-beta.1"));   // release > its prerelease
  TEST_ASSERT_FALSE(isStrictlyNewer("0.2.0-beta.1", "0.2.0"));  // prerelease < release
  TEST_ASSERT_TRUE(isStrictlyNewer("0.2.0-beta.2", "0.2.0-beta.1"));
}

void test_unparseable_fails_closed(void) {
  TEST_ASSERT_FALSE(isStrictlyNewer("garbage", "0.1.3"));
  TEST_ASSERT_FALSE(isStrictlyNewer("0.1.4", "not-a-version"));
  TEST_ASSERT_EQUAL_INT(-2, compareSemver("1.2", "0.1.0")); // too few components
}

void test_v_prefix_tolerated(void) {
  TEST_ASSERT_TRUE(isStrictlyNewer("v0.1.4", "v0.1.3"));
}

// The anti-rollback floor needs to tell "this is a valid version" apart from
// "this compares less than what I want". A corrupt stored floor used to be
// indistinguishable from a legitimately-blocking floor, which meant a garbage
// NVS value made the device permanently rollback-blocked with no recovery short
// of a USB reflash.
void test_is_valid_semver(void) {
  TEST_ASSERT_TRUE(isValidSemver("0.9.1"));
  TEST_ASSERT_TRUE(isValidSemver("1.2.3"));
  TEST_ASSERT_TRUE(isValidSemver("v0.1.4"));
  TEST_ASSERT_TRUE(isValidSemver("1.0.0-beta.1"));

  TEST_ASSERT_FALSE(isValidSemver(""));
  TEST_ASSERT_FALSE(isValidSemver("garbage"));
  TEST_ASSERT_FALSE(isValidSemver("not-a-version"));
  TEST_ASSERT_FALSE(isValidSemver("1.2"));       // too few components
  TEST_ASSERT_FALSE(isValidSemver("0x0A"));
  TEST_ASSERT_FALSE(isValidSemver("9.1.1 "));    // trailing space
}

void setup() {
  UNITY_BEGIN();
  RUN_TEST(test_strictly_newer);
  RUN_TEST(test_equal_or_older_blocked);
  RUN_TEST(test_prerelease_ordering);
  RUN_TEST(test_unparseable_fails_closed);
  RUN_TEST(test_v_prefix_tolerated);
  RUN_TEST(test_is_valid_semver);
  UNITY_END();
}

void loop() {}
