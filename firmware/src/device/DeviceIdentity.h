#pragma once

#include <Arduino.h>

namespace jkbmsr {

class DeviceIdentity {
 public:
  // Generates a fresh, cryptographically random device ID. Call once on
  // first boot and persist the result via ConfigStore — never derive device
  // identity from a publicly observable value like a WiFi MAC address, which
  // would let an attacker enumerate or pre-register a real device's ID
  // before it ever boots.
  String generateDeviceId() const;

  // Generates a fresh, human-typeable claim secret (8 chars, high-entropy,
  // ambiguity-free alphabet). Minted once on first boot and persisted; the
  // backend requires it before binding this device to a user account. Printed
  // on the label / serial and handed to the browser via the provisioning
  // redirect URL so the happy path never asks the user to type it.
  String generateClaimCode() const;

  String hardwareId() const;
  // Stable, platform-namespaced factory identity. The cloud HMACs this value
  // before storing it and never treats it as an authentication credential.
  String hardwareFingerprint() const;
  String hardwarePlatform() const;
  String hardwareModel() const;
};

}  // namespace jkbmsr
