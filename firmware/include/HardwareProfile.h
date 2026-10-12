#pragma once

#include <Arduino.h>

// Build environments provide these values. Defaults preserve compatibility
// for local Arduino builds that do not use PlatformIO.
#ifndef JKBMSR_TARGET_HARDWARE
#define JKBMSR_TARGET_HARDWARE "esp32-classic-4mb"
#endif

#ifndef JKBMSR_HARDWARE_PLATFORM
#define JKBMSR_HARDWARE_PLATFORM "esp32"
#endif

#ifndef JKBMSR_BOARD_PROFILE
#define JKBMSR_BOARD_PROFILE "generic"
#endif

#ifndef JKBMSR_MAX_GPIO_PIN
#define JKBMSR_MAX_GPIO_PIN 39
#endif

#ifndef JKBMSR_PROVISIONING_BUTTON_PIN
#define JKBMSR_PROVISIONING_BUTTON_PIN 0
#endif

namespace jkbmsr {

constexpr const char* kTargetHardware = JKBMSR_TARGET_HARDWARE;
constexpr const char* kHardwarePlatform = JKBMSR_HARDWARE_PLATFORM;
constexpr const char* kBoardProfile = JKBMSR_BOARD_PROFILE;
constexpr int kMaxGpioPin = JKBMSR_MAX_GPIO_PIN;
constexpr int kProvisioningButtonPin = JKBMSR_PROVISIONING_BUTTON_PIN;

}  // namespace jkbmsr
