// Host-side support translation units for scripts/run-host-tests.sh.
#include "Arduino.h"
#include "unity.h"
#include "WiFi.h"

int unity_failures = 0;
int unity_tests = 0;
HardwareSerial Serial;
// Globals the WiFi shim declares extern, mirroring how Serial is provided here.
// Unused by the pure-decode suites; they exist so the provisioning suite's
// WiFi/ESP surface resolves without a per-suite support .cpp.
WiFiClass WiFi;
EspClass ESP;

void setup();
void loop();

int main() {
  setup();
  loop();
  return unity_failures;
}
