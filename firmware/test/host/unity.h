#pragma once
// Minimal Unity shim — NOT the real Unity.
//
// The suites in test/test_*/ are written against Arduino's Unity build. This
// header provides the small assertion subset they use so the same source can
// be compiled and executed on a host with scripts/run-host-tests.sh. Keeping
// the suites' source unchanged is the whole point: the bug this addresses is
// that CI only ever *compiled* them.
//
// Semantics match Unity closely enough for these assertions: a failing
// assertion is recorded and the test continues, so one run reports every
// failure rather than stopping at the first.

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>

extern int unity_failures;
extern int unity_tests;

#define UNITY_BEGIN() (unity_tests = 0, unity_failures = 0)
#define UNITY_END() (printf("%d test(s), %d failure(s)\n", unity_tests, unity_failures), unity_failures)

#define RUN_TEST(f)          \
  do {                       \
    unity_tests++;           \
    printf("  %-56s", #f);  \
    f();                     \
  } while (0)

static inline void unityCheck(bool ok, const char* expr, const char* file, int line) {
  if (ok) {
    printf(" ok\n");
  } else {
    printf(" FAIL  (%s:%d) %s\n", file, line, expr);
    unity_failures++;
  }
}

#define TEST_FAIL_MESSAGE(m) unityCheck(false, (m), __FILE__, __LINE__)
#define TEST_ASSERT_TRUE(x) unityCheck((x) ? true : false, #x, __FILE__, __LINE__)
#define TEST_ASSERT_FALSE(x) unityCheck((x) ? false : true, "!" #x, __FILE__, __LINE__)
#define TEST_ASSERT_NULL(x) unityCheck((x) == nullptr, #x " == null", __FILE__, __LINE__)
#define TEST_ASSERT_NOT_NULL(x) unityCheck((x) != nullptr, #x " != null", __FILE__, __LINE__)
#define TEST_ASSERT_EQUAL_UINT8(e, a) unityCheck(static_cast<uint8_t>(e) == static_cast<uint8_t>(a), #e " == " #a, __FILE__, __LINE__)
#define TEST_ASSERT_EQUAL_UINT16(e, a) unityCheck(static_cast<uint16_t>(e) == static_cast<uint16_t>(a), #e " == " #a, __FILE__, __LINE__)
#define TEST_ASSERT_EQUAL_UINT32(e, a) unityCheck(static_cast<uint32_t>(e) == static_cast<uint32_t>(a), #e " == " #a, __FILE__, __LINE__)
#define TEST_ASSERT_EQUAL_HEX8(e, a) unityCheck(static_cast<uint8_t>(e) == static_cast<uint8_t>(a), #e " == " #a, __FILE__, __LINE__)
#define TEST_ASSERT_EQUAL_HEX16(e, a) unityCheck(static_cast<uint16_t>(e) == static_cast<uint16_t>(a), #e " == " #a, __FILE__, __LINE__)
#define TEST_ASSERT_EQUAL_HEX32(e, a) unityCheck(static_cast<uint32_t>(e) == static_cast<uint32_t>(a), #e " == " #a, __FILE__, __LINE__)
#define TEST_ASSERT_EQUAL_INT(e, a) unityCheck(static_cast<int>(e) == static_cast<int>(a), #e " == " #a, __FILE__, __LINE__)
#define TEST_ASSERT_EQUAL(e, a) unityCheck((e) == (a), #e " == " #a, __FILE__, __LINE__)
#define TEST_ASSERT_EQUAL_UINT(e, a) unityCheck(static_cast<unsigned>(e) == static_cast<unsigned>(a), #e " == " #a, __FILE__, __LINE__)
#define TEST_ASSERT_EQUAL_STRING(e, a) unityCheck(strcmp((e), (a)) == 0, #e " == " #a, __FILE__, __LINE__)
#define TEST_ASSERT_EQUAL_MEMORY(e, a, n) unityCheck(memcmp((e), (a), (n)) == 0, #e " == " #a, __FILE__, __LINE__)
#define TEST_ASSERT_GREATER_THAN(t, a) unityCheck((a) > (t), #a " > " #t, __FILE__, __LINE__)
#define TEST_ASSERT_LESS_THAN(t, a) unityCheck((a) < (t), #a " < " #t, __FILE__, __LINE__)
#define TEST_ASSERT_GREATER_OR_EQUAL_UINT32(t, a) \
  unityCheck(static_cast<uint32_t>(a) >= static_cast<uint32_t>(t), #a " >= " #t, __FILE__, __LINE__)
#define TEST_ASSERT_FLOAT_WITHIN(tol, e, a) \
  unityCheck(std::fabs(static_cast<double>(e) - static_cast<double>(a)) <= static_cast<double>(tol), \
             #e " ~= " #a, __FILE__, __LINE__)

// NOTE: delay() deliberately lives in test/host/Arduino.h, not here — several
// protocol sources include both, and defining it twice is a hard error.
