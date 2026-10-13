// Self-test for the deny predicate. Run: node --test (from this directory).
//
// The predicate, not the fetch wrapper, is the load-bearing logic, so it is a
// pure function (isDenied) and is asserted directly. A control is included: if
// the allowed-host cases ever started returning true, the block would take a
// whole host offline, and this suite is what fails loudly instead.
import assert from "node:assert/strict";
import { test } from "node:test";

import { isDenied } from "./index.js";

const url = (s) => new URL(s);

test("denies every firmware path on the CDN host", () => {
  for (const path of [
    "/firmware",
    "/firmware/",
    "/firmware/esp32-classic-4mb/latest.json",
    "/firmware/esp32-s3-16mb/v0.9.6/firmware.bin",
    "/firmware/../firmware/x",
  ]) {
    assert.equal(isDenied(url("https://cdn.jkbmsr.com" + path)), true, path);
  }
});

test("passes through everything else on the CDN host", () => {
  for (const path of [
    "/",
    "/docs/",
    "/ota/esp32-classic-4mb-latest.json",
    "/mobile/android/",
    "/firmware-old/x", // lookalike prefix, never a firmware URL
  ]) {
    assert.equal(isDenied(url("https://cdn.jkbmsr.com" + path)), false, path);
  }
});

test("control: never denies the firmware path on a different host", () => {
  assert.equal(isDenied(url("https://api.jkbmsr.com/firmware/x")), false);
  assert.equal(isDenied(url("https://jkbmsr.com/firmware/x")), false);
});
