# Layered on sdkconfig.defaults + sdkconfig.defaults.secure for
# env:idf-secureboot-c3. Omits CONFIG_ESP32_REV_MIN_3 (see
# sdkconfig.defaults.secureboot, classic-ESP32-only) -- ESP32-C3 is RISC-V,
# not the Xtensa ESP32 silicon that erratum applies to, and has no chip-
# revision gate for Secure Boot v2.
#
# Dev signing key is gitignored -- generate with:
#   scripts/generate-secure-boot-dev-key.sh
# See docs/phase2-encryption-spec.md (P2-4) and docs/secure-bringup.md.

CONFIG_SECURE_BOOT=y
CONFIG_SECURE_BOOT_V2_ENABLED=y
CONFIG_SECURE_BOOT_BUILD_SIGNED_BINARIES=y
CONFIG_SECURE_BOOT_SIGNING_KEY="keys/secure_boot_signing_key.pem"
CONFIG_SECURE_BOOT_FLASH_BOOTLOADER_DEFAULT=y

# Signature block needs room before the partition table.
CONFIG_PARTITION_TABLE_OFFSET=0xD000
CONFIG_PARTITION_TABLE_CUSTOM=y
CONFIG_PARTITION_TABLE_CUSTOM_FILENAME="partitions-secureboot.csv"
CONFIG_PARTITION_TABLE_FILENAME="partitions-secureboot.csv"
