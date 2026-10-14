#include <Arduino.h>
#include <time.h>

#include "AppConfig.h"
#include "BatteryTelemetry.h"
#include "FirmwareVersion.h"
#include "HardwareProfile.h"
#include "bms/BmsBleClient.h"
#include "bms/JkBmsBleClient.h"
#include "cloud/DeviceRegistrationClient.h"
#include "cloud/TelemetryClient.h"
#include "cloud/RemoteConfigClient.h"
#include "config/ConfigStore.h"
#include "debug/DebugLog.h"
#include "device/DeviceIdentity.h"
#include "network/WifiManager.h"
#include "network/WifiRetryPolicy.h"
#include "ota/OtaClient.h"
#include "esp_ota_ops.h"
#include "ota/VersionCompare.h"
#include "provisioning/CaptivePortal.h"
#include "provisioning/ProvisioningManager.h"
#include "provisioning/ResetTrigger.h"

using namespace jkbmsr;

ConfigStore configStore;
WifiManager wifiManager;
JkBmsBleClient bmsBleClient;
DeviceIdentity deviceIdentity;
DeviceRegistrationClient deviceRegistrationClient(kApiBaseUrl);
TelemetryClient telemetryClient(kApiBaseUrl);
RemoteConfigClient remoteConfigClient(kApiBaseUrl);
OtaClient otaClient(kApiBaseUrl);
ProvisioningManager provisioner;
CaptivePortal captivePortal;
ResetTrigger resetTrigger;
DeviceConfig config;
uint32_t lastTelemetryMs = 0;
// Epoch second of the last wall-clock-aligned telemetry send (0 = none
// yet) — see telemetryDue() below.
time_t lastTelemetryEpoch = 0;
uint32_t lastConfigFetchMs = 0;
uint32_t lastOtaCheckMs = 0;
bool firstOtaCheckDone = false;
uint32_t lastCloudBootstrapAttemptMs = 0;
uint32_t lastHeartbeatMs = 0;
uint32_t identityDiscoveryUntilMs = 0;
uint32_t lastDeviceAuthMs = 0;
String activeBleVendor = "";

// The gateway is JK-BMS only. A stored bmsVendor from before the product went
// JK-only (old NVS state or a stale cloud config) must never select another
// protocol: fall back to JK with a clear serial log line, never brick, and
// never silently mis-speak another vendor's protocol.
bool isKnownBmsVendor(const String& vendor) {
  return vendor == "jk";
}

// Retry cadence while offline is now owned by network/WifiRetryPolicy.h +
// connectWithRetry()/recoverFromWifiFailure() below: try for
// kWifiConnectWindowMs, then restart and retry, opening the local AP for a
// bounded window every kWifiRestartsBeforeProvisioning failed boots.
constexpr uint32_t kProvisioningRetryTimeoutMs = 300000;
constexpr uint32_t kCloudBootstrapRetryMs = 30000;
constexpr uint32_t kRemoteConfigIntervalMs = 60000;
// Heartbeat cadence while the BMS link is down. Must stay well under the
// dashboard's 5-minute online window; kept above the telemetry interval so a
// dark BMS doesn't fill the telemetry table at full rate.
constexpr uint32_t kHeartbeatIntervalMs = 120000;
constexpr uint32_t kTimeSyncTimeoutMs = 15000;
// Bumped from 2 to 10 minutes (2026-08-21): the browser flasher's real
// end-to-end flash -> reset -> open-Improv-session -> claim flow routinely
// took longer than 2 minutes on its own (esptool-js transfer time, reset/
// reconnect, plus normal human latency clicking through the UI), so the
// window was expiring before the "RequestDeviceInfo" round-trip ever
// happened. Once expired, loop() below stops calling provisioner.poll()
// entirely -- no error, no state change, the device just goes silent on
// Improv Serial -- which is what made the WiFi step hang indefinitely
// rather than fail visibly.
constexpr uint32_t kIdentityDiscoveryWindowMs = 600000;
constexpr uint32_t kDeviceTokenRefreshMs = 45 * 60 * 1000;
// 2024-01-01 UTC. TLS certificate validity cannot be checked against the
// ESP32's default epoch-era clock; accept any plausible post-build time.
constexpr time_t kMinimumValidEpoch = 1704067200;

bool systemClockValid() {
  return time(nullptr) >= kMinimumValidEpoch;
}

bool ensureSystemClock() {
  if (systemClockValid()) {
    return true;
  }

  logInfo("Synchronizing system clock");
  configTime(0, 0, "pool.ntp.org", "time.cloudflare.com", "time.google.com");
  const uint32_t startedAtMs = millis();
  while (!systemClockValid() && millis() - startedAtMs < kTimeSyncTimeoutMs) {
    delay(100);
  }

  if (!systemClockValid()) {
    logWarn("System clock synchronization timed out; cloud TLS deferred");
    return false;
  }

  logInfo("System clock synchronized");
  return true;
}

// Fires once per wall-clock interval boundary (e.g. every :00/:01/:02... at
// a 1-minute interval, every :00/:05/:10... at 5 minutes) instead of a
// relative "N ms since last send" timer, so every gateway on the same
// interval reports at the same clock boundaries rather than whatever
// second it happened to boot on - the dashboard/export line points up
// across devices this way. The epoch is itself boundary-aligned (1970-01-01
// 00:00:00 UTC), so plain modulo does the job with no calendar/timezone
// math. Falls back to the previous relative-timer behavior for the brief
// pre-NTP-sync window at boot, before systemClockValid() is true.
bool telemetryDue() {
  const uint32_t intervalMs = config.telemetryIntervalMs;
  if (intervalMs == 0) {
    return false;
  }
  if (!systemClockValid()) {
    if (millis() - lastTelemetryMs < intervalMs) {
      return false;
    }
    lastTelemetryMs = millis();
    return true;
  }
  const time_t intervalSeconds = intervalMs / 1000;
  const time_t now = time(nullptr);
  if (intervalSeconds <= 0 || now % intervalSeconds != 0 || now == lastTelemetryEpoch) {
    return false;
  }
  lastTelemetryEpoch = now;
  return true;
}

// Soft re-provision: drop Wi-Fi + JWT so the device re-enters provisioning.
// Device ID, claim code, firmware floor, and device secret are preserved.
void clearWifiCredentials(DeviceConfig& target) {
  target.wifiSsid = "";
  target.wifiPassword = "";
  target.deviceToken = "";
}

// Factory reset clears user configuration but preserves the logical gateway
// identity and rotating secret. Identity is protected state: clearing it here
// would strand an already-claimed gateway and could duplicate its license.
void clearFactoryAuth(DeviceConfig& target) {
  clearWifiCredentials(target);
}

// Apply any pending BOOT long-press. Returns true if Wi-Fi creds were cleared
// and provisioning should run.
bool applyResetTrigger() {
  if (!resetTrigger.provisioningRequested()) {
    return false;
  }

  if (resetTrigger.factoryResetRequested()) {
    logWarn("Factory reset requested (BOOT held ~10s)");
    clearFactoryAuth(config);
  } else {
    logWarn("Re-provision requested (BOOT held ~5s)");
    clearWifiCredentials(config);
  }
  configStore.save(config);
  resetTrigger.clear();
  return true;
}

// Runs Improv Serial (USB) and SoftAP captive-portal provisioning in parallel
// until Wi-Fi is connected (or timeoutMs elapses; 0 means wait indefinitely).
// On success the captured credentials are persisted. Serial logging is
// suppressed for the duration because Improv shares UART0 and text would
// corrupt its binary stream.
bool runProvisioning(uint32_t timeoutMs) {
  const String apSsid = CaptivePortal::softApSsid(config.deviceId);
  logInfo("Entering WiFi provisioning mode");
  logInfo("SoftAP SSID: " + apSsid);
  // Derived from this device's claim code, not a shared constant. The user
  // needs it to join the AP, and it is printed on serial (physical access) —
  // but it is not published in docs or packaging, so knowing the device ID
  // from the SSID is no longer enough to join someone's setup network.
  logInfo("SoftAP password: " + CaptivePortal::softApPassword(config.deviceId, config.claimCode));

  setLoggingEnabled(false);
  provisioner.begin(Serial, config.deviceId, config.claimCode);
  captivePortal.begin(config.deviceId, config.claimCode);

  const auto tryConnect = [](const String& s, const String& p) {
    return wifiManager.connect(s, p, kWifiConnectTimeoutMs);
  };
  const auto scanNetworks = [](ProvisioningManager::Network* networks, size_t capacity) {
    WifiScanResult results[kMaxWifiScanResults];
    const size_t count = wifiManager.scan(results, min(capacity, kMaxWifiScanResults));
    for (size_t index = 0; index < count; ++index) {
      networks[index].ssid = results[index].ssid;
      networks[index].rssi = results[index].rssi;
      networks[index].secure = results[index].secure;
    }
    return count;
  };
  // Same underlying WifiManager::scan() the Improv path above uses, just
  // without the Network-struct translation -- CaptivePortal::ScanFn's
  // signature already matches WifiManager::scan() exactly.
  const auto captiveScanNetworks = [](WifiScanResult* results, size_t capacity) {
    return wifiManager.scan(results, capacity);
  };
  // Persist an account-bound claim token the moment the signed-in flasher hands
  // it over, so it survives the Wi-Fi step and is presented at registration.
  // Logging is suppressed during provisioning (Improv shares UART0 with it), so
  // this deliberately does not log.
  const auto persistClaimToken = [](const String& token) {
    if (token.length() == 0) {
      return;
    }
    config.claimToken = token;
    configStore.save(config);
  };

  const uint32_t startMs = millis();
  String ssid;
  String password;
  bool connected = false;
  while (true) {
    // Keep watching BOOT so a factory-reset hold during an open portal still
    // lands; credentials capture below takes priority once submitted.
    resetTrigger.poll();

    if (provisioner.poll(tryConnect, ssid, password, scanNetworks, persistClaimToken) ||
        captivePortal.poll(tryConnect, captiveScanNetworks, ssid, password)) {
      config.wifiSsid = ssid;
      config.wifiPassword = password;
      configStore.save(config);
      connected = true;
      break;
    }
    if (timeoutMs != 0 && millis() - startMs >= timeoutMs) {
      break;
    }
    delay(10);
  }

  captivePortal.end();
  setLoggingEnabled(true);
  if (connected) {
    // Credentials came from the local path (Improv Serial / captive portal),
    // not a cloud push. Flag it so the backend can yield a stale remote target
    // to a person who fixed the device on site; cleared once reported.
    config.wifiLocalProvisioned = true;
    config.wifiRestartCount = 0;
    configStore.save(config);
    logInfo("WiFi provisioned and connected");
  } else {
    logWarn("Provisioning window closed without credentials");
  }
  return connected;
}

// Attempts to join the saved/desired Wi-Fi for up to kWifiConnectWindowMs,
// retrying every kWifiRetryDelayMs. Returns true on success. The window is
// what lets the caller tell "slow to associate" apart from "this network does
// not work" and restart rather than waiting forever.
bool connectWithRetry() {
  WifiRetryPolicy policy(WifiRetryTimings{kWifiConnectWindowMs, kWifiRetryDelayMs});
  policy.beginWindow(millis());
  while (!policy.windowExpired(millis())) {
    if (policy.attemptDue(millis())) {
      policy.noteAttempt(millis());
      if (wifiManager.connect(config.wifiSsid, config.wifiPassword, kWifiConnectTimeoutMs)) {
        config.wifiRestartCount = 0;
        return true;
      }
    }
    delay(50);
  }
  logWarn("WiFi connect window elapsed after " + String(policy.attempts()) + " attempt(s)");
  return false;
}

// Called after a full connect window failed. Below the restart threshold it
// restarts the gateway immediately (the requested "restart and try again").
// At the threshold it opens the local AP for a bounded window so a person on
// site can still fix the credentials, then resumes the retry loop. Returns
// true only when that local provisioning window produced a working connection
// (the restart branches do not return).
bool recoverFromWifiFailure() {
  config.wifiRestartCount += 1;
  if (config.wifiRestartCount <= static_cast<uint32_t>(kWifiRestartsBeforeProvisioning)) {
    logWarn("WiFi unreachable; restarting to retry (restart " + String(config.wifiRestartCount) + ")");
    configStore.save(config);
    delay(1000);
    ESP.restart();
    return false;
  }

  config.wifiRestartCount = 0;
  configStore.save(config);
  logWarn("WiFi still unreachable after repeated restarts; opening local provisioning");
  if (!runProvisioning(kLocalProvisioningWindowMs)) {
    logWarn("Local provisioning window closed without connecting; restarting to retry");
    delay(1000);
    ESP.restart();
    return false;
  }
  return true;
}

void normalizeBmsConfig(DeviceConfig& target) {
  if (!isKnownBmsVendor(target.bmsVendor)) {
    logWarn("Stored BMS vendor '" + target.bmsVendor +
            "' is not supported (JK-BMS only); falling back to 'jk'");
    target.bmsVendor = "jk";
  }
}

// Starts the JK BLE client. The BMS link is Bluetooth (BLE) only — there is
// no wired transport to configure. Called at boot, after a remote-config or
// auth update, and after a device-auth refresh.
void applyBmsConfig() {
  normalizeBmsConfig(config);
  if (activeBleVendor.length() > 0 && activeBleVendor != config.bmsVendor) {
    bmsBleClient.stop();
  }
  bmsBleClient.begin(config.bmsBleAddress);
  activeBleVendor = config.bmsVendor;
  logInfo("JK-BMS BLE configured");
}

void applyDeviceAuthResult(const DeviceRegistrationResult& result) {
  config.deviceToken = result.token;
  if (result.deviceSecret.length() > 0) {
    config.deviceSecret = result.deviceSecret;
  }
  config.telemetryIntervalMs = result.telemetryIntervalMs;
  config.otaEnabled = result.otaEnabled;
  config.bmsVendor = result.bmsVendor;
  applyBmsConfig();
  configStore.save(config);
}

void ensureDeviceAuth(bool forceRefresh = false) {
  if ((!forceRefresh && config.deviceToken.length() > 0) || !wifiManager.connected() || !systemClockValid()) {
    return;
  }

  DeviceRegistrationResult result;
  if (config.deviceSecret.length() > 0 &&
      deviceRegistrationClient.loginDevice(
          config.deviceId,
          config.deviceSecret,
          deviceIdentity.hardwareFingerprint(),
          deviceIdentity.hardwarePlatform(),
          deviceIdentity.hardwareModel(),
          kTargetHardware,
          kBoardProfile,
          kFirmwareVersion,
          result)) {
    applyDeviceAuthResult(result);
    lastDeviceAuthMs = millis();
    return;
  }

  // Account-bound claim token, provisioned over serial by the signed-in web
  // flasher. Present only until the first successful registration consumes it;
  // after that the device authenticates with its rotating secret like any
  // other deployed gateway.
  const bool hadClaimToken = config.claimToken.length() > 0;
  if (deviceRegistrationClient.registerDevice(
          config.deviceId,
          deviceIdentity.hardwareId(),
          deviceIdentity.hardwareFingerprint(),
          deviceIdentity.hardwarePlatform(),
          deviceIdentity.hardwareModel(),
          kTargetHardware,
          kBoardProfile,
          kFirmwareVersion,
          config.claimCode,
          config.claimToken,
          result)) {
    // Registration succeeded, so the backend either bound this account or
    // refused the token — either way it is single-use and must not be retried.
    // A failed registration (network error) leaves it in place for the retry.
    if (hadClaimToken) {
      config.claimToken = "";
    }
    applyDeviceAuthResult(result);
    lastDeviceAuthMs = millis();
  }
}

void processRemoteWifiActions(const RemoteWifiActions& actions) {
  if (actions.scanRequestId.length() > 0) {
    logInfo("Scanning nearby 2.4 GHz WiFi networks");
    WifiScanResult results[kMaxWifiScanResults];
    const size_t count = wifiManager.scan(results, kMaxWifiScanResults);
    if (remoteConfigClient.reportWifiScan(
          config.deviceToken, actions.scanRequestId, wifiManager.currentSsid(), results, count)) {
      logInfo("WiFi scan results uploaded (" + String(count) + " networks)");
    } else {
      logWarn("WiFi scan result upload failed; will retry");
    }
  }

  if (actions.changeRequestId.length() == 0 || actions.candidateSsid.length() == 0) return;

  const String oldSsid = config.wifiSsid;
  const String oldPassword = config.wifiPassword;
  logInfo("Testing requested WiFi network: " + actions.candidateSsid);
  if (!wifiManager.connect(actions.candidateSsid, actions.candidatePassword, kWifiConnectTimeoutMs)) {
    logWarn("Requested WiFi connection failed; restoring previous network");
    wifiManager.connect(oldSsid, oldPassword, kWifiConnectTimeoutMs);
    remoteConfigClient.reportWifiChange(config.deviceToken, actions.changeRequestId, "failed",
                                        wifiManager.currentSsid(), "Could not connect to requested network");
    return;
  }

  DeviceConfig candidate = config;
  candidate.wifiSsid = actions.candidateSsid;
  candidate.wifiPassword = actions.candidatePassword;
  if (!configStore.save(candidate)) {
    wifiManager.connect(oldSsid, oldPassword, kWifiConnectTimeoutMs);
    remoteConfigClient.reportWifiChange(config.deviceToken, actions.changeRequestId, "failed",
                                        wifiManager.currentSsid(), "Could not save WiFi credentials");
    return;
  }

  // This authenticated HTTPS callback proves the candidate network can reach
  // JKBMSR Cloud. If it fails, restore both NVS and the previous live link.
  if (!remoteConfigClient.reportWifiChange(config.deviceToken, actions.changeRequestId, "succeeded",
                                           wifiManager.currentSsid(), "Connected and verified")) {
    configStore.save(config);
    wifiManager.connect(oldSsid, oldPassword, kWifiConnectTimeoutMs);
    remoteConfigClient.reportWifiChange(config.deviceToken, actions.changeRequestId, "failed",
                                        wifiManager.currentSsid(), "Cloud verification failed");
    logWarn("Requested WiFi could not reach cloud; previous network restored");
    return;
  }

  config = candidate;
  logInfo("WiFi change verified and saved; restarting");
  delay(1000);
  ESP.restart();
}

// Applies a persistent remote Wi-Fi target delivered by GET /device/config.
// Called only while online. Re-applies exactly once per revision (the applied
// revision is persisted in NVS), then restarts to attempt the new network
// from a clean radio state; connectWithRetry()/recoverFromWifiFailure() then
// keep retrying it. Secured and open networks both work: an open target has an
// empty password, which WifiManager::connect sends as a nullptr passphrase.
void applyRemoteWifiTarget(const RemoteWifiActions& actions) {
  if (actions.desiredRevision.length() == 0) return;
  if (actions.desiredRevision == config.wifiDesiredRevision) return;
  if (actions.desiredSsid.length() == 0) return;

  logInfo("Applying remote WiFi target: " + actions.desiredSsid +
          (actions.desiredOpen ? " (open)" : ""));
  config.wifiSsid = actions.desiredSsid;
  config.wifiPassword = actions.desiredOpen ? String("") : actions.desiredPassword;
  config.wifiDesiredRevision = actions.desiredRevision;
  config.wifiLocalProvisioned = false;
  config.wifiRestartCount = 0;
  configStore.save(config);
  delay(1000);
  ESP.restart();
}

void processRemoteOtaAction(const RemoteWifiActions& actions) {
  if (actions.otaUpdateRequestId.length() == 0) return;
  if (!config.otaEnabled) {
    remoteConfigClient.reportOtaCommand(
      config.deviceToken, actions.otaUpdateRequestId, "failed", "OTA updates are disabled");
    return;
  }
  logInfo("Remote OTA update check requested");
  if (!remoteConfigClient.reportOtaCommand(
        config.deviceToken, actions.otaUpdateRequestId, "checking", "Checking for latest firmware")) {
    logWarn("Could not acknowledge remote OTA request; will retry");
    return;
  }

  lastOtaCheckMs = millis();
  firstOtaCheckDone = true;
  otaClient.checkForUpdate(config.deviceToken, kFirmwareVersion, config.firmwareVersionFloor);
  const OtaStatus& status = otaClient.status();
  remoteConfigClient.reportOtaCommand(
    config.deviceToken,
    actions.otaUpdateRequestId,
    status.lastCheckSucceeded ? "completed" : "failed",
    status.lastResult);
}

#ifndef UNIT_TEST

void setup() {
  Serial.begin(115200);

  logInfo("JKBMSR firmware starting");
  logInfo(String("Firmware version ") + kFirmwareVersion);
  logInfo(String("Hardware target ") + kTargetHardware + " (" + kBoardProfile + ")");
  configStore.begin();
  config = configStore.load();

  resetTrigger.begin(kProvisioningButtonPin);
  // Sample once up front so a hold that started just after boot is observed
  // before we decide whether to enter provisioning.
  resetTrigger.poll();

  bool configDirty = false;

  if (config.deviceId.length() == 0) {
    // First boot (or a device that predates the random-ID migration): mint a
    // random identity now and persist it immediately, rather than deriving
    // one from the WiFi MAC address, which would be guessable from public
    // Espressif OUI ranges.
    config.deviceId = deviceIdentity.generateDeviceId();
    configDirty = true;
    logInfo("Generated device ID: " + config.deviceId);
  }

  if (config.claimCode.length() == 0) {
    // Mint the per-device claim secret alongside the ID on first boot. It is
    // handed to the browser during provisioning and required by the backend to
    // bind this device to an account.
    config.claimCode = deviceIdentity.generateClaimCode();
    configDirty = true;
    logInfo("Generated device claim code: " + config.claimCode);
  }

  // Printed unconditionally on every boot (not just the first, where the
  // "Generated..." lines above already cover it) so a device that already
  // has an identity -- e.g. re-flashed, or claimed on a browser session that
  // missed the original generation lines -- can still be claimed manually
  // from the serial log alone. Same trust model as the Improv "physical-
  // possession claim handoff" (ProvisioningManager::sendDeviceInfo): anyone
  // with physical USB access already gets this over Improv regardless.
  logInfo("Gateway ID: " + config.deviceId);
  logInfo("Claim code: " + config.claimCode);

  // Anti-rollback floor: the highest version this device has ever run. Raise
  // it to the running firmware version whenever we boot something newer (which
  // includes the first boot after a successful OTA), and never lower it.
  //
  // A stored floor that is not a parseable version is corrupt, not a high
  // floor. isStrictlyNewer() fails closed on unparseable input, so a garbage
  // value would never be repaired *and* would make every future OTA compare
  // against nonsense — permanently "rollback-blocked" with no path back except
  // a USB reflash. NVS is unauthenticated on every non-encrypted target, so
  // treat an unparseable floor as absent and re-seed it from the running
  // version. This fails *toward* accepting the running firmware, which is
  // correct: we are not downgrading, we are already booted on it.
  if (!isValidSemver(config.firmwareVersionFloor)) {
    if (config.firmwareVersionFloor.length() > 0) {
      logWarn("Stored firmware floor is unparseable (" + config.firmwareVersionFloor +
              "); resetting to " + kFirmwareVersion);
    }
    config.firmwareVersionFloor = kFirmwareVersion;
    configDirty = true;
  } else if (isStrictlyNewer(kFirmwareVersion, config.firmwareVersionFloor)) {
    config.firmwareVersionFloor = kFirmwareVersion;
    configDirty = true;
  }

  if (configDirty) {
    configStore.save(config);
  }

  // Honor a BOOT long-press observed at startup before attempting Wi-Fi.
  applyResetTrigger();

  applyBmsConfig();

  // A device with no stored WiFi credentials enters provisioning instead of
  // idling forever unable to connect. A device WITH credentials tries them for
  // a bounded window; if that fails it restarts and retries (opening the local
  // AP every few boots), rather than falling straight back to setup mode.
  bool online = false;
  if (!config.wifiConfigured()) {
    online = runProvisioning(0);
  } else {
    online = connectWithRetry();
    if (online) {
      // A web flash preserves NVS. In that case Wi-Fi and cloud credentials
      // already exist, so the normal provisioning flow would never return the
      // device ID/claim code and the signed-in browser could not bind it. For
      // kIdentityDiscoveryWindowMs after boot, answer an explicit Improv
      // device-info request without reopening the AP or disturbing the
      // working Wi-Fi link.
      provisioner.begin(Serial, config.deviceId, config.claimCode, false, true);
      identityDiscoveryUntilMs = millis() + kIdentityDiscoveryWindowMs;
    } else {
      // The saved/desired network did not come up. Recover rather than sit in
      // setup mode: restart and retry, with a bounded local AP window every
      // few attempts so the device stays fixable on site.
      online = recoverFromWifiFailure();
    }
  }

  if (online) {
    logInfo("WiFi connected");
    if (ensureSystemClock()) {
      // NVS may contain a short-lived token from a previous boot. Always
      // authenticate with the persistent rotating secret at boot so a gateway
      // powered from a charger never starts with an expired cloud session.
      ensureDeviceAuth(true);
    }
    lastCloudBootstrapAttemptMs = millis();
  } else {
    logWarn("WiFi not connected");
  }

  // Reaching here means setup() ran to completion without crashing or
  // watchdog-resetting -- confirm this image is good so ESP-IDF's rollback
  // logic (CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE, sdkconfig.defaults) doesn't
  // revert to the previous OTA slot on next boot. Deliberately not gated on
  // `online`: a WiFi outage shouldn't roll back an otherwise-healthy image.
  // A no-op (returns ESP_ERR_NOT_SUPPORTED, harmless) on any build whose
  // bootloader was compiled without rollback enabled.
  esp_ota_mark_app_valid_cancel_rollback();
}

void loop() {
  if (identityDiscoveryUntilMs != 0 && static_cast<int32_t>(identityDiscoveryUntilMs - millis()) > 0) {
    String unusedSsid;
    String unusedPassword;
    // An already-Wi-Fi-configured gateway answers Improv here without opening
    // the AP. Accept a flash-time account token if one arrives so a re-flash
    // against a board with saved credentials still records it (it is used only
    // if the board ever re-registers).
    provisioner.poll({}, unusedSsid, unusedPassword, {},
                     [](const String& token) {
                       if (token.length() > 0 && token != config.claimToken) {
                         config.claimToken = token;
                         configStore.save(config);
                       }
                     });
  }

  resetTrigger.poll();
  if (applyResetTrigger()) {
    if (runProvisioning(0)) {
      ensureDeviceAuth(true);
    }
    delay(10);
    return;
  }

  // WiFi recovery: while offline, run the same bounded connect window as boot.
  // If it fails, recoverFromWifiFailure() restarts the gateway (retrying
  // forever) and periodically opens the local AP so the device stays fixable.
  if (!wifiManager.connected()) {
    if (config.wifiConfigured()) {
      if (connectWithRetry()) {
        if (ensureSystemClock()) {
          ensureDeviceAuth(true);
        }
        lastCloudBootstrapAttemptMs = millis();
      } else if (recoverFromWifiFailure()) {
        if (ensureSystemClock()) {
          ensureDeviceAuth(true);
        }
        lastCloudBootstrapAttemptMs = millis();
      }
    } else if (runProvisioning(kProvisioningRetryTimeoutMs)) {
      if (ensureSystemClock()) {
        ensureDeviceAuth(true);
      }
      lastCloudBootstrapAttemptMs = millis();
    }
    delay(10);
    return;
  }

  // Initial NTP or auth can fail transiently even though WiFi remains up.
  // Retry both without requiring a reboot or a WiFi disconnect/reconnect.
  if ((!systemClockValid() || config.deviceToken.length() == 0) &&
      millis() - lastCloudBootstrapAttemptMs >= kCloudBootstrapRetryMs) {
    lastCloudBootstrapAttemptMs = millis();
    if (ensureSystemClock()) {
      ensureDeviceAuth(true);
    }
  }

  const bool cloudReady = systemClockValid() && config.deviceToken.length() > 0;

  // Device JWTs are deliberately short-lived. Renew them well before expiry
  // using the persistent per-device secret, even if Wi-Fi never drops.
  const bool authRefreshDue = config.deviceSecret.length() > 0 &&
      ((lastDeviceAuthMs == 0 && millis() - lastCloudBootstrapAttemptMs >= kCloudBootstrapRetryMs) ||
       (lastDeviceAuthMs != 0 && millis() - lastDeviceAuthMs >= kDeviceTokenRefreshMs));
  if (authRefreshDue) {
    lastCloudBootstrapAttemptMs = millis();
    ensureDeviceAuth(true);
  }

  // The BMS link is Bluetooth (BLE) only; drive the JK client every loop
  // iteration (it owns its own scan/connect state machine).
  bmsBleClient.loop();

  BatteryTelemetry telemetry;
  if (telemetryDue()) {
    const bool haveSample = bmsBleClient.poll(telemetry);
    // With no BMS answering, still report in at a lower cadence so
    // the dashboard shows the gateway online (BMS link flagged down) instead
    // of "last seen never".
    const bool heartbeatDue = millis() - lastHeartbeatMs >= kHeartbeatIntervalMs;
    if (cloudReady && (haveSample || heartbeatDue)) {
      const OtaStatus& otaStatus = otaClient.status();
      telemetry.otaLastCheckAtMs = otaStatus.lastCheckAtMs;
      telemetry.otaLastCheckSucceeded = otaStatus.lastCheckSucceeded;
      telemetry.otaUpdateAvailable = otaStatus.updateAvailable;
      telemetry.otaUpdateApplied = otaStatus.updateApplied;
      telemetry.otaOfferedVersion = otaStatus.offeredVersion;
      telemetry.otaLastResult = otaStatus.lastResult;
      // The JK client's own scan/connect/decode state.
      const BmsBleStatus bleStatus = bmsBleClient.status();
      telemetry.bleState = bleStatus.state;
      telemetry.bleAddress = bleStatus.address;
      telemetry.bleAdvertisedName = bleStatus.advertisedName;
      telemetry.bleHardwareVersion = bleStatus.hardwareVersion;
      telemetry.bleSoftwareVersion = bleStatus.softwareVersion;
      telemetry.bleRssi = bleStatus.rssi;
      telemetry.bleAddressType = bleStatus.addressType;
      telemetry.bleFramesDecoded = bleStatus.framesDecoded;
      telemetry.bleChecksumErrors = bleStatus.checksumErrors;
      telemetry.bleLastFrameAtMs = bleStatus.lastFrameAtMs;
      telemetry.bleLastScanAtMs = bleStatus.lastScanAtMs;
      telemetry.bleLastConnectedAtMs = bleStatus.lastConnectedAtMs;
      telemetry.bleLastError = bleStatus.lastError;
      telemetry.bleCandidateCount = min<uint8_t>(bleStatus.candidateCount, kMaxBleCandidateCount);
      for (uint8_t index = 0; index < telemetry.bleCandidateCount; ++index) {
        telemetry.bleCandidateAddresses[index] = bleStatus.candidates[index].address;
        telemetry.bleCandidateNames[index] = bleStatus.candidates[index].name;
        telemetry.bleCandidateRssi[index] = bleStatus.candidates[index].rssi;
        telemetry.bleCandidateAddressTypes[index] = bleStatus.candidates[index].addressType;
      }
      if (telemetryClient.upload(config.deviceToken, telemetry)) {
        lastHeartbeatMs = millis();
      } else if (telemetryClient.authRejected()) {
        // The server rejected our token (e.g. a signing-secret rotation). Drop
        // it and force a fresh login so telemetry resumes — otherwise the
        // persisted token is presented forever and the gateway looks
        // permanently offline.
        logWarn("Telemetry token rejected; forcing device re-login");
        config.deviceToken = "";
        ensureDeviceAuth(true);
      }
    }
  }

  if (cloudReady && millis() - lastConfigFetchMs >= kRemoteConfigIntervalMs) {
    lastConfigFetchMs = millis();
    RemoteWifiActions wifiActions;
    if (remoteConfigClient.fetch(config.deviceToken, config, &wifiActions)) {
      applyBmsConfig();
      configStore.save(config);
      // Apply a changed persistent target first — it restarts the gateway, so
      // the one-shot actions below would otherwise race the reboot.
      applyRemoteWifiTarget(wifiActions);
      processRemoteWifiActions(wifiActions);
      processRemoteOtaAction(wifiActions);
    }
    // Report our own Wi-Fi state while we can reach the cloud, so the backend
    // can tell "reached the cloud on the new network" apart from silence.
    // Best-effort: a failure here is not retried until the next cycle.
    remoteConfigClient.reportWifiState(
        config.deviceToken, "connected", wifiManager.currentSsid(),
        wifiManager.lastError(), config.wifiLocalProvisioned);
    if (config.wifiLocalProvisioned) {
      config.wifiLocalProvisioned = false;
      configStore.save(config);
    }
  }

  // First OTA check ~2 minutes after boot (a power cycle is the natural
  // "update now" gesture), then every 6 hours.
  const bool otaCheckDue = firstOtaCheckDone ? millis() - lastOtaCheckMs >= 21600000
                                             : millis() >= 120000;
  if (cloudReady && config.otaEnabled && config.deviceToken.length() > 0 && otaCheckDue) {
    lastOtaCheckMs = millis();
    firstOtaCheckDone = true;
    otaClient.checkForUpdate(config.deviceToken, kFirmwareVersion, config.firmwareVersionFloor);
  }

  delay(10);
}

#endif
