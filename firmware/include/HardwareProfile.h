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

// Matches the JKBMSR_HAS_BLE/JKBMSR_HAS_OTA convention already established
// by env:esp8266-nodemcu (see platformio.ini) rather than introducing a
// second "SUPPORTS" naming for the same concept.
#ifndef JKBMSR_HAS_BLE
#define JKBMSR_HAS_BLE 1
#endif

#ifndef JKBMSR_HAS_OTA
#define JKBMSR_HAS_OTA 1
#endif

#ifndef JKBMSR_DEFAULT_BMS_RX_PIN
#define JKBMSR_DEFAULT_BMS_RX_PIN 16
#endif

#ifndef JKBMSR_DEFAULT_BMS_TX_PIN
#define JKBMSR_DEFAULT_BMS_TX_PIN 17
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
constexpr bool kHasBle = JKBMSR_HAS_BLE != 0;
constexpr bool kHasOta = JKBMSR_HAS_OTA != 0;
constexpr int kDefaultBmsRxPin = JKBMSR_DEFAULT_BMS_RX_PIN;
constexpr int kDefaultBmsTxPin = JKBMSR_DEFAULT_BMS_TX_PIN;
constexpr int kMaxGpioPin = JKBMSR_MAX_GPIO_PIN;
constexpr int kProvisioningButtonPin = JKBMSR_PROVISIONING_BUTTON_PIN;

}  // namespace jkbmsr
