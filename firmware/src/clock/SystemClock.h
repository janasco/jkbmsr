#pragma once

#include <Arduino.h>

namespace jkbmsr {

// The system clock is UTC. This module only decides how that UTC is *rendered*
// — in the serial log today — so a gateway in Cebu and one in Berlin print the
// time their owner expects while the epoch underneath stays comparable.
//
// The value is a POSIX TZ string (the format setenv("TZ") accepts), not an IANA
// name: the ESP32 has no tz database, so "Asia/Manila" cannot be resolved on the
// device. Examples:
//
//   UTC0                          no offset, no DST — the default
//   PST-8                         fixed UTC+8, no DST (Asia/Manila, Singapore)
//   CET-1CEST,M3.5.0,M10.5.0/3    Central Europe, with the EU DST rules
//
// A trailing rule-less form is deliberate: a fixed offset is right for most of
// the year in the zones our customers are in, and a wrong-but-stable offset is
// easier to explain than a DST rule that silently drifts.
void applyTimeZone(const String& posix);

// The currently applied string, for logs and the settings report.
const String& currentTimeZone();

// Accepts only the characters a POSIX TZ string can contain. Pure, so it is
// host-tested: a value that fails this check is refused rather than passed to
// setenv, because setenv with a malformed TZ leaves the clock reading UTC with
// no error to notice.
bool isValidPosixTimeZone(const String& posix);

}  // namespace jkbmsr
