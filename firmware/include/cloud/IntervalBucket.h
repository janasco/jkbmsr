#pragma once

#include <ctime>

namespace jkbmsr {

/// Which wall-clock interval a moment belongs to.
///
/// The upload gate used to ask "is `now % interval == 0`", which is true for
/// exactly ONE second per interval and only if the loop happens to look at that
/// instant. With a 60 s interval that is usually caught; with a 300 s trial
/// interval it is a 1-in-300 chance per boundary, and the upload itself takes
/// seconds (a real gateway's upload landed six seconds after its boundary), so a
/// busy loop misses boundary after boundary. A field gateway on the trial then
/// reported LESS often than the free tier, which is the opposite of the point.
///
/// A bucket is "which interval number are we in": it changes exactly once per
/// boundary and stays changed until the next one, so a late loop still uploads,
/// once, instead of waiting for a coincidence.
inline time_t intervalBucket(time_t now, time_t intervalSeconds) {
  if (intervalSeconds <= 0) {
    return 0;
  }
  return now / intervalSeconds;
}

/// True when this moment is in a different interval than [lastBucket], i.e. a
/// boundary has been crossed since the last upload.
inline bool crossedIntervalBoundary(time_t now, time_t intervalSeconds, time_t lastBucket) {
  if (intervalSeconds <= 0) {
    return false;
  }
  return intervalBucket(now, intervalSeconds) != lastBucket;
}

}  // namespace jkbmsr
