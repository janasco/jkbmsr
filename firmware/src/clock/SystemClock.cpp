#include "SystemClock.h"

#include <time.h>

namespace jkbmsr {

namespace {

String g_timeZone = "UTC0";
constexpr size_t kMaxTimeZoneLength = 48;

}  // namespace

bool isValidPosixTimeZone(const String& posix) {
  // Empty, overlong, or containing anything a POSIX TZ string cannot hold. The
  // charset covers names (letters), the angle-bracket quoted form, offsets
  // (digits, +, -), rule fields (",", ".", "/") and the sign/colon splits.
  if (posix.length() == 0 || posix.length() > kMaxTimeZoneLength) {
    return false;
  }
  // '/' is legal only inside a DST rule time ("M10.5.0/3"), and a rule time can
  // only exist after a ','. This is what separates "CET-1CEST,M3.5.0,M10.5.0/3"
  // from "Asia/Manila": an IANA name has a slash and no rule, and libc would
  // silently ignore the whole string rather than reject it.
  if (posix.indexOf('/') >= 0 && posix.indexOf(',') < 0) {
    return false;
  }
  for (size_t i = 0; i < posix.length(); ++i) {
    const char c = posix[i];
    const bool ok = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                    (c >= '0' && c <= '9') || c == '+' || c == '-' || c == ':' ||
                    c == ',' || c == '.' || c == '/' || c == '<' || c == '>';
    if (!ok) {
      return false;
    }
  }
  return true;
}

void applyTimeZone(const String& posix) {
  if (!isValidPosixTimeZone(posix)) {
    // Refuse rather than apply: a malformed TZ is ignored by libc without an
    // error, so the device would keep printing UTC while the settings page said
    // otherwise — the exact silent disagreement this module exists to remove.
    return;
  }
  setenv("TZ", posix.c_str(), 1);
  tzset();
  g_timeZone = posix;
}

const String& currentTimeZone() {
  return g_timeZone;
}

}  // namespace jkbmsr
