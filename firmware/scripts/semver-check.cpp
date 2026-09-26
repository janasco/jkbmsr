// Host harness for the firmware's own version-string validation.
//
// The release script must decide whether a version string is acceptable
// *before* it becomes an R2 object key, a D1 SQL literal, a GitHub release tag
// and a directory name. Rather than reimplement that decision in bash --
// where a second, subtly different parser would drift from the one the devices
// use -- this links the real src/ota/VersionCompare.cpp and calls the real
// jkbmsr::isValidSemver(), built against the same Arduino String shim that
// scripts/run-host-tests.sh uses. One parser, one answer.
//
// This is a compile-and-run tool, not a unit test: test_version_compare
// already covers isValidSemver's behaviour. The point here is that the
// release pipeline uses the same implementation the firmware does.
//
// Output is a single word on stdout: "valid" or "invalid".

#include <Arduino.h>

#include <cstdio>

#include "ota/VersionCompare.h"

int main(int argc, char** argv) {
  if (argc != 2) {
    std::fprintf(stderr, "usage: %s <version-string>\n", argv[0]);
    return 2;
  }
  const String version(argv[1]);
  std::printf("%s\n", jkbmsr::isValidSemver(version) ? "valid" : "invalid");
  return 0;
}
