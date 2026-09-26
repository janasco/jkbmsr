#pragma once

#include <Arduino.h>

namespace jkbmsr {

// Semantic-version comparison used for OTA anti-rollback.
//
// Returns -2 if either input cannot be parsed as major.minor.patch,
// otherwise -1 / 0 / 1 for a<b / a==b / a>b. Ordering follows semver: a
// release ranks above its own pre-release (1.0.0 > 1.0.0-beta.1).
int compareSemver(const String& a, const String& b);

// True when `version` parses as major.minor.patch[(-|+)prerelease].
// Exposed separately from compareSemver() because the anti-rollback floor needs
// to distinguish "this is a valid version" from "this compares less than what I
// want". A corrupt stored floor must be *repaired*; it is not the same as a
// floor that legitimately blocks a downgrade, and compareSemver()'s -2 sentinel
// cannot tell those apart from the caller's side.
bool isValidSemver(const String& version);

// True only if `candidate` parses as a valid version AND is strictly greater
// than `floor`. Fails closed: returns false if either version is unparseable,
// so an OTA is never applied on an ambiguous comparison.
bool isStrictlyNewer(const String& candidate, const String& floor);

}  // namespace jkbmsr
