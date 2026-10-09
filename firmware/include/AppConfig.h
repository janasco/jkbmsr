#pragma once

#include <Arduino.h>

#include "HardwareProfile.h"

namespace jkbmsr {

constexpr const char* kApiBaseUrl = "https://api.jkbmsr.com";
constexpr uint32_t kDefaultTelemetryIntervalMs = 60000;
// Bumped from 15 to 25 seconds (2026-08-21): confirmed on real hardware
// during provisioning bring-up that L2 association + WPA2 handshake can
// complete in under 200ms while the DHCP lease that follows takes much
// longer than 15s to arrive, specifically while the SoftAP captive portal
// is kept up in parallel (AP_STA radio-time contention) -- the STA showed
// "connected" at the driver level well within the old timeout, but no IP
// had been assigned by the time WifiManager::connect() gave up, so a
// correctly-entered password was reported back to the user as a connect
// failure.
constexpr uint32_t kWifiConnectTimeoutMs = 25000;
// Remote-Wi-Fi connect/retry/restart policy (see network/WifiRetryPolicy.h).
// After a saved/desired network fails for kWifiConnectWindowMs, the gateway
// restarts and tries again — repeatedly, per the product requirement that it
// must never sit permanently in setup/AP mode. Every
// kWifiRestartsBeforeProvisioning failed boots it opens the local AP for a
// bounded window so a person on site can still fix the credentials.
constexpr uint32_t kWifiConnectWindowMs = 180000;      // ~3 minutes of attempts per boot
constexpr uint32_t kWifiRetryDelayMs = 5000;           // pause between attempts
constexpr int kWifiRestartsBeforeProvisioning = 5;
constexpr uint32_t kLocalProvisioningWindowMs = 300000;  // bounded AP window (5 min)
// TLS handshake cap. The verified handshake (bundle-based chain validation)
// is heavier than the old insecure path, and flaky WiFi (RV/off-grid) can
// stall it; bound it so a hung handshake can't wedge the loop.
constexpr uint32_t kTlsHandshakeTimeoutSeconds = 20;
// TLS body-read cap, in seconds. Distinct from the handshake cap: a server can
// complete the negotiation and then stall or truncate mid-body, and every HTTP
// call site in this firmware is synchronous, so an unbounded read blocks loop()
// until the loop-task watchdog resets the device. Generous enough for the OTA
// download over slow links, since this is an *idle* timeout (reset on each
// chunk) rather than a total-transfer cap.
constexpr uint32_t kTlsReadTimeoutSeconds = 30;
constexpr int kJkBmsRxPin = kDefaultBmsRxPin;
constexpr int kJkBmsTxPin = kDefaultBmsTxPin;
constexpr uint32_t kJkBmsBaudRate = 115200;
constexpr uint32_t kMinBmsBaudRate = 9600;
constexpr uint32_t kMaxBmsBaudRate = 115200;

}  // namespace jkbmsr
