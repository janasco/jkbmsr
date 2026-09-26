#pragma once

#include "net/PlatformNetwork.h"

namespace jkbmsr {

// Configures a WiFiClientSecure to verify the server's certificate chain —
// against the embedded Mozilla root-CA bundle on ESP32 (see data/cert/ and
// scripts/regenerate-ca-bundle.sh), or a small embedded 2-root trust list on
// ESP8266 (see SecureClient.cpp; that core's WiFiClientSecure is BearSSL-
// based and has no equivalent bundle API, nor the RAM for a full one) —
// replacing the previous setInsecure() calls that accepted any certificate
// and left every cloud connection open to a trivial man-in-the-middle.
//
// Call this on every WiFiClientSecure before begin()/connect(). Centralized
// so the fleet's TLS trust policy lives in exactly one place.
void configureSecureClient(GatewaySecureClient& client);

}  // namespace jkbmsr
