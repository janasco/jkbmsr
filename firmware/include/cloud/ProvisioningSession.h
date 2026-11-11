#pragma once

#include <Arduino.h>

namespace jkbmsr {

// The provisioning session, without a radio.
//
// The radio cannot be host-tested, so everything that decides *whether* a write
// is allowed lives here and is tested with a fake clock. The one guarantee this
// class exists for: no credential write is accepted before the per-boot setup
// code has been presented correctly.
enum class ProvisioningState {
  advertising,
  connected,
  authenticated,
  applying,
  rebooting,
  registering,
  running,
  failed,
};

inline const char* provisioningStateName(ProvisioningState state) {
  switch (state) {
    case ProvisioningState::advertising:
      return "advertising";
    case ProvisioningState::connected:
      return "connected";
    case ProvisioningState::authenticated:
      return "authenticated";
    case ProvisioningState::applying:
      return "applying";
    case ProvisioningState::rebooting:
      return "rebooting";
    case ProvisioningState::registering:
      return "registering";
    case ProvisioningState::running:
      return "running";
    case ProvisioningState::failed:
      return "failed";
  }
  return "unknown";
}

enum class SetupCodeResult {
  accepted,
  rejected,
  lockedOut,
  notConnected,
};

// When the setup service may be visible at all.
//
// The owner's correction to the first draft, and it is the right one: a gateway
// that is running must not be provisionable, both because anyone in range could
// bind it to their account and because advertising costs radio time that belongs
// to the pack link. So the service exists only while the gateway cannot reach the
// network.
//
// The grace period is not decoration. A two-second WiFi blip must not open
// provisioning to the neighbourhood: jamming a 2.4 GHz network is easy, and
// without the grace an attacker could force the window open and then provision
// the device. Sixty seconds is longer than the existing reconnect backoff's first
// attempts, so a blip recovers on its own and never advertises.
constexpr uint32_t kWiFiLossGraceMs = 60000;

inline bool shouldAdvertiseProvisioning(bool hasWiFiCredentials, bool wifiConnected,
                                        uint32_t msSinceWiFiLost) {
  // Never configured: nothing to protect yet, and this is the first-boot case.
  if (!hasWiFiCredentials) {
    return true;
  }
  if (wifiConnected) {
    return false;
  }
  return msSinceWiFiLost >= kWiFiLossGraceMs;
}

class ProvisioningSession {
 public:
  // Sixty seconds for the credentials after a correct code, and sixty seconds of
  // silence before an idle connection is dropped. Both bound the window in which
  // a phone holds a share of a radio that also carries the BMS link.
  static constexpr uint32_t kAuthTimeoutMs = 60000;
  static constexpr uint32_t kIdleTimeoutMs = 60000;
  static constexpr uint8_t kMaxFailedAttempts = 3;

  explicit ProvisioningSession(const String& setupCode) : setupCode_(setupCode) {}

  ProvisioningState state() const { return state_; }
  uint8_t failedAttempts() const { return failedAttempts_; }

  // One connection at a time. A second phone is refused rather than queued: the
  // radio is shared with the pack, so the cost of a second connection is paid by
  // telemetry, not by the person who opened the app twice.
  bool onConnected(uint32_t nowMs) {
    if (state_ == ProvisioningState::advertising) {
      state_ = ProvisioningState::connected;
      connectedAtMs_ = nowMs;
      lastActivityMs_ = nowMs;
      failedAttempts_ = 0;
      errorReason_ = "";
      return true;
    }
    return false;
  }

  void onDisconnected() {
    if (state_ == ProvisioningState::advertising) {
      return;
    }
    // A connection that drops mid-apply must not leave the state believing the
    // payload is committed.
    state_ = ProvisioningState::advertising;
    errorReason_ = "";
    failedAttempts_ = 0;
  }

  SetupCodeResult submitSetupCode(const String& code, uint32_t nowMs) {
    if (state_ != ProvisioningState::connected) {
      return SetupCodeResult::notConnected;
    }
    lastActivityMs_ = nowMs;
    if (code == setupCode_ && setupCode_.length() == 6) {
      state_ = ProvisioningState::authenticated;
      authenticatedAtMs_ = nowMs;
      return SetupCodeResult::accepted;
    }
    ++failedAttempts_;
    if (failedAttempts_ >= kMaxFailedAttempts) {
      // Locked out: the caller drops the link, and a new scan starts from zero.
      state_ = ProvisioningState::advertising;
      return SetupCodeResult::lockedOut;
    }
    return SetupCodeResult::rejected;
  }

  // True only after a correct code and before the timeout. This is the single
  // gate the write path must consult.
  bool credentialsWritable() const { return state_ == ProvisioningState::authenticated; }

  // authenticated -> applying. False if the window closed or the state is wrong.
  bool commit(uint32_t nowMs) {
    if (state_ != ProvisioningState::authenticated) {
      return false;
    }
    if (nowMs - authenticatedAtMs_ > kAuthTimeoutMs) {
      state_ = ProvisioningState::advertising;
      return false;
    }
    lastActivityMs_ = nowMs;
    state_ = ProvisioningState::applying;
    return true;
  }

  // applying -> rebooting, once the credentials are stored.
  bool onStored() {
    if (state_ != ProvisioningState::applying) {
      return false;
    }
    state_ = ProvisioningState::rebooting;
    return true;
  }

  // rebooting -> registering, after the restart.
  bool onRebootComplete() {
    if (state_ != ProvisioningState::rebooting) {
      return false;
    }
    state_ = ProvisioningState::registering;
    return true;
  }

  // registering -> running, once the claim token has been accepted.
  bool onRegistered() {
    if (state_ != ProvisioningState::registering) {
      return false;
    }
    state_ = ProvisioningState::running;
    return true;
  }

  // Any state -> failed, with a reason the app renders. The reason set matches
  // the protocol doc.
  void fail(const char* reason) {
    state_ = ProvisioningState::failed;
    errorReason_ = reason != nullptr ? reason : "payload";
  }

  const String& errorReason() const { return errorReason_; }

  // Drop an idle or expired window. Returns true when the session itself moved
  // back to advertising, so the caller can tear down the connection.
  bool tick(uint32_t nowMs) {
    if (state_ == ProvisioningState::connected && nowMs - lastActivityMs_ > kIdleTimeoutMs) {
      state_ = ProvisioningState::advertising;
      return true;
    }
    if (state_ == ProvisioningState::authenticated && nowMs - authenticatedAtMs_ > kAuthTimeoutMs) {
      state_ = ProvisioningState::advertising;
      return true;
    }
    return false;
  }

 private:
  String setupCode_;
  ProvisioningState state_ = ProvisioningState::advertising;
  String errorReason_;
  uint8_t failedAttempts_ = 0;
  uint32_t connectedAtMs_ = 0;
  uint32_t authenticatedAtMs_ = 0;
  uint32_t lastActivityMs_ = 0;
};

}  // namespace jkbmsr
