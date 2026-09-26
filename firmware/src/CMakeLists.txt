# Main firmware component for the Arduino-as-ESP-IDF-component build (env:idf
# and its per-chip/secure/secureboot variants — see platformio.ini).
# Keep this list in sync when adding/removing .cpp files under src/.
# The pure-Arduino env:dev does not use this file (PlatformIO auto-discovers).

set(JKBMSR_SRCS
  "main.cpp"
  "bms/AntBmsDecoder.cpp"
  "bms/BasenBmsDecoder.cpp"
  "bms/DalyBmsParser.cpp"
  "bms/DalyD2Decoder.cpp"
  "bms/JbdBmsParser.cpp"
  "bms/Jk02Decoder.cpp"
  "bms/JkBmsParser.cpp"
  "bms/KsBmsDecoder.cpp"
  "bms/LolanBmsDecoder.cpp"
  "bms/SeplosBleDecoder.cpp"
  "bms/TianpowerBmsDecoder.cpp"
  "cloud/DeviceRegistrationClient.cpp"
  "cloud/RemoteConfigClient.cpp"
  "cloud/TelemetryClient.cpp"
  "config/ConfigStore.cpp"
  "debug/DebugLog.cpp"
  "device/DeviceIdentity.cpp"
  "net/SecureClient.cpp"
  "network/WifiManager.cpp"
  "ota/OtaClient.cpp"
  "ota/VersionCompare.cpp"
  "provisioning/CaptivePortal.cpp"
  "provisioning/ImprovProtocol.cpp"
  "provisioning/ProvisioningManager.cpp"
  "provisioning/ResetTrigger.cpp"
)

set(JKBMSR_REQUIRES "")

# BLE BMS clients (and the bt component they need) are excluded on chips with
# no Bluetooth radio -- ESP32-S2 today, via sdkconfig.defaults.no-ble
# (env:idf-s2 and its secure variants) setting CONFIG_BT_ENABLED=n. Mirrors
# the plain-Arduino env:esp32-s2-4mb's build_src_filter exclusion of the same
# four files.
if(CONFIG_BT_ENABLED)
  list(APPEND JKBMSR_SRCS
    "bms/AntBmsBleClient.cpp"
    "bms/BasenBmsBleClient.cpp"
    "bms/DalyBmsBleClient.cpp"
    "bms/JbdBmsBleClient.cpp"
    "bms/JkBmsBleClient.cpp"
    "bms/KsBmsBleClient.cpp"
    "bms/LolanBmsBleClient.cpp"
    "bms/SeplosBmsBleClient.cpp"
    "bms/TianpowerBmsBleClient.cpp"
  )
  list(APPEND JKBMSR_REQUIRES bt)
endif()

idf_component_register(
  SRCS ${JKBMSR_SRCS}
  INCLUDE_DIRS
    "."
    "../include"
  REQUIRES ${JKBMSR_REQUIRES}
)

# CA trust store: env:idf uses the ESP-IDF mbedtls certificate bundle
# (CONFIG_MBEDTLS_CERTIFICATE_BUNDLE) already linked by the framework —
# see SecureClient.cpp. Do NOT target_add_binary_data the Arduino-path
# bundle here; PlatformIO's SCons layer conflicts with that embed rule.
