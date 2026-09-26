#include "VersionCompare.h"

namespace jkbmsr {

namespace {

struct SemVer {
  long major = 0;
  long minor = 0;
  long patch = 0;
  String prerelease;
  bool valid = false;
};

bool parseNonNegInt(const String& value, long& out) {
  if (value.length() == 0) {
    return false;
  }
  for (size_t index = 0; index < value.length(); ++index) {
    const char c = value[index];
    if (c < '0' || c > '9') {
      return false;
    }
  }
  out = value.toInt();
  return true;
}

SemVer parseSemver(const String& raw) {
  SemVer parsed;
  String s = raw;
  s.trim();
  if (s.startsWith("v") || s.startsWith("V")) {
    s = s.substring(1);
  }

  const int dash = s.indexOf('-');
  const String core = dash >= 0 ? s.substring(0, dash) : s;
  const String pre = dash >= 0 ? s.substring(dash + 1) : "";

  const int firstDot = core.indexOf('.');
  if (firstDot < 0) {
    return parsed;
  }
  const int secondDot = core.indexOf('.', firstDot + 1);
  if (secondDot < 0) {
    return parsed;
  }

  long major = 0;
  long minor = 0;
  long patch = 0;
  if (!parseNonNegInt(core.substring(0, firstDot), major) ||
      !parseNonNegInt(core.substring(firstDot + 1, secondDot), minor) ||
      !parseNonNegInt(core.substring(secondDot + 1), patch)) {
    return parsed;
  }

  parsed.major = major;
  parsed.minor = minor;
  parsed.patch = patch;
  parsed.prerelease = pre;
  parsed.valid = true;
  return parsed;
}

}  // namespace

bool isValidSemver(const String& version) {
  return parseSemver(version).valid;
}

int compareSemver(const String& a, const String& b) {
  const SemVer va = parseSemver(a);
  const SemVer vb = parseSemver(b);
  if (!va.valid || !vb.valid) {
    return -2;
  }

  if (va.major != vb.major) {
    return va.major < vb.major ? -1 : 1;
  }
  if (va.minor != vb.minor) {
    return va.minor < vb.minor ? -1 : 1;
  }
  if (va.patch != vb.patch) {
    return va.patch < vb.patch ? -1 : 1;
  }

  const bool aPre = va.prerelease.length() > 0;
  const bool bPre = vb.prerelease.length() > 0;
  if (aPre != bPre) {
    // The version WITH a pre-release ranks lower than the plain release.
    return aPre ? -1 : 1;
  }
  if (!aPre && !bPre) {
    return 0;
  }

  const int pre = va.prerelease.compareTo(vb.prerelease);
  return pre == 0 ? 0 : (pre < 0 ? -1 : 1);
}

bool isStrictlyNewer(const String& candidate, const String& floor) {
  return compareSemver(candidate, floor) == 1;
}

}  // namespace jkbmsr
