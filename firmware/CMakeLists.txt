# The following lines of boilerplate have to be in this exact order for
# cmake to work correctly with PlatformIO's Arduino-as-ESP-IDF-component
# build (env:idf). See docs/phase2-encryption-spec.md.
cmake_minimum_required(VERSION 3.16.0)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(jkbmsr_firmware)
