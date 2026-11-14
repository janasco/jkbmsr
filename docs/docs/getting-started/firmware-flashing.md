# Flash the firmware

Flashing happens in the browser, over USB, at
[web.jkbmsr.com/flash](https://web.jkbmsr.com/flash). There is nothing to install,
and no local toolchain is needed.

## Before you start

- A **desktop** computer running **Chrome** or **Edge**. Firefox and Safari have
  no Web Serial and cannot open a USB port.
- A **USB data cable**. Some cables only carry power, and those look like a board
  that never appears.
- An **ESP32 gateway board** and a **signed-in JK BMS Remote account**.
- A 2.4 GHz **Wi-Fi network** you can give it the password for.

## Five steps

1. **Open the flasher.** Sign in at <https://web.jkbmsr.com>, then open
   [web.jkbmsr.com/flash](https://web.jkbmsr.com/flash).
2. **Connect the board** with the USB cable and close any serial monitor that has
   the port open. Choose the board you have; the flasher offers seven targets and
   the label on the module says which one.
3. **Press Firmware Flasher → Connect and install**, then pick the port when the
   browser asks. The write takes a minute or two.
4. **Give it Wi-Fi.** The gateway restarts and advertises `JKBMSR-Setup-XXXX`. Set
   it up in one of three ways, all available at the same time:
   - **the app**: Settings → Tools → Add a gateway, then the six digit code the
     console printed;
   - **this page**: the flasher hands the Wi-Fi details over USB;
   - **a browser only**: join `JKBMSR-Setup-XXXX`, password is the claim code in
     the console.
5. **Watch it appear.** The gateway is added to the account it was set up from,
   automatically. It shows on the dashboard once it reports, and the first reading
   usually arrives within a minute of joining the network.

There is **no claim code to type** when you set it up while signed in. The one
printed in the console exists for the browser-only path and for a gateway that was
set up elsewhere.

## After flashing, if something looks wrong

- **No port appears.** Try another cable first: a charge-only cable is the most
  common cause. Then another USB port, and close other programs that use serial.
- **The flash fails part way.** Reconnect and try again. A failed write does not
  leave the board unusable; it simply has no new firmware.
- **It flashed but never appears on the dashboard.** Open **Diagnostics** in the
  sidebar, connect the same port, and press **Restart device**. The console shows
  the boot log, which says whether it is joining Wi-Fi, failing to authenticate, or
  up but unable to reach the battery.
- **It worked, then went quiet.** Check the dashboard's status first: *Online, no
  recent data* means the gateway is running and the battery link is the problem;
  *Offline* means the gateway itself has stopped reporting.

## Re-flashing an existing gateway

Flash the same way. The stored Wi-Fi and the gateway's identity are kept, so it
comes back as the same gateway with the same history and plan. Only a factory reset
(hold **BOOT** for about ten seconds) creates a new identity, which then needs
setting up again.

## Safety

- Keep the gateway clear of high-current battery wiring while flashing.
- Never power the ESP32 directly from battery pack voltage.
- Flash over USB, from a computer. There is no over-the-air first install.
