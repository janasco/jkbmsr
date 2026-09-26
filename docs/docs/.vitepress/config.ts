import { defineConfig } from "vitepress";

export default defineConfig({
  title: "JK BMS Remote Docs",
  description: "Documentation for JK BMS Remote, an independent remote monitoring solution for JK-BMS products.",
  cleanUrls: true,
  lastUpdated: true,
  // docs/internal/*.md are engineering notes (deployment state, release
  // runbooks), not user documentation. They are excluded from the build
  // entirely, not merely unlinked from the nav.
  //
  // Removing the nav entries was not enough: VitePress still renders every
  // markdown file under the source root, so /internal/architecture.html,
  // /internal/deployment.html, /internal/release-process.html and
  // /internal/firmware-release-runbook.html were all built and reachable by
  // direct URL on the public docs site. These pages describe internal
  // infrastructure and release procedure, so "not in the sidebar" was never a
  // sufficient answer.
  //
  // The files stay in the tree for maintainers and are served locally by
  // `npm run docs:dev`. Nothing under docs/ links to them (verified), so this
  // does not orphan any page. If an internal page is ever needed in the
  // published site, move it out of docs/internal/ deliberately rather than
  // widening this glob.
  srcExclude: ["internal/**"],
  // Hard-default to light (matching the rest of the platform) while keeping the
  // theme toggle. VitePress treats an unset preference as "auto" and follows the
  // OS; seeding it to "light" on first visit before paint overrides that. Runs
  // regardless of order vs VitePress's own appearance script — it only acts when
  // no preference is stored, so the toggle and later choices are untouched.
  head: [
    [
      "link",
      { rel: "icon", type: "image/svg+xml", href: "/favicon.svg" },
    ],
    [
      "link",
      { rel: "apple-touch-icon", href: "/logos/app-icon-1024.png" },
    ],
    [
      "script",
      {},
      "try{var k='vitepress-theme-appearance';if(!localStorage.getItem(k)){localStorage.setItem(k,'light');document.documentElement.classList.remove('dark');}}catch(e){}",
    ],
  ],
  themeConfig: {
    logo: "/favicon.svg",
    siteTitle: "JK BMS Remote Docs",
    nav: [
      { text: "Overview", link: "/index" },
      { text: "API", link: "/api/index" },
      { text: "Firmware", link: "/firmware/downloads" },
      { text: "Getting Started", link: "/getting-started/first-device-setup" },
      { text: "Troubleshooting", link: "/troubleshooting/index" },
    ],
    sidebar: [
      {
        text: "Overview",
        items: [
          { text: "Documentation Home", link: "/index" },
          { text: "Product Overview", link: "/product-overview" },
        ],
      },
      {
        text: "Apps & Plans",
        items: [
          { text: "Apps", link: "/apps/" },
          { text: "Plans & Pricing", link: "/pricing" },
        ],
      },
      {
        text: "API",
        items: [
          { text: "API Index", link: "/api/index" },
          { text: "Authentication", link: "/api/authentication" },
          { text: "Devices", link: "/api/devices" },
          { text: "Telemetry", link: "/api/telemetry" },
          { text: "Config", link: "/api/config" },
          { text: "OTA", link: "/api/ota" },
        ],
      },
      {
        text: "Cloud",
        items: [
          { text: "Cloud Setup", link: "/cloud/cloud-setup" },
          { text: "OTA Update Process", link: "/cloud/ota-update-process" },
        ],
      },
      {
        text: "Firmware",
        items: [
          { text: "Firmware Downloads", link: "/firmware/downloads" },
          { text: "OTA Validation", link: "/firmware/ota-validation" },
          { text: "Verify Checksum", link: "/firmware/verify-checksum" },
          { text: "Release Notes", link: "/firmware/release-notes" },
          { text: "Supported Hardware", link: "/firmware/supported-hardware" },
        ],
      },
      {
        text: "Getting Started",
        items: [
          { text: "First Device Setup", link: "/getting-started/first-device-setup" },
          { text: "ESP32 Gateway Setup", link: "/getting-started/esp32-gateway-setup" },
          { text: "Firmware Flashing", link: "/getting-started/firmware-flashing" },
          { text: "Device Registration", link: "/getting-started/device-registration" },
          { text: "JK-BMS Wiring", link: "/getting-started/jk-bms-wiring" },
          { text: "UART Pinout Warnings", link: "/getting-started/uart-pinout-warnings" },
        ],
      },
      {
        text: "Safety",
        items: [
          { text: "Battery Safety", link: "/safety/battery-safety" },
          { text: "OTA Safety", link: "/safety/ota-safety" },
          { text: "Wiring Safety", link: "/safety/wiring-safety" },
        ],
      },
      {
        text: "Troubleshooting",
        items: [
          { text: "Troubleshooting Index", link: "/troubleshooting/index" },
          { text: "Claim and Onboard Issues", link: "/troubleshooting/claim-and-onboard-issues" },
          { text: "WiFi Issues", link: "/troubleshooting/wifi-issues" },
          { text: "BMS Connection Issues", link: "/troubleshooting/bms-connection-issues" },
          { text: "Telemetry Issues", link: "/troubleshooting/telemetry-issues" },
          { text: "OTA Issues", link: "/troubleshooting/ota-issues" },
          { text: "OTA Support Checklist", link: "/troubleshooting/ota-support-checklist" },
        ],
      },
      // docs/internal/*.md is excluded from the build via srcExclude above —
      // see the note there. The files remain in the tree for maintainers.
    ],
    socialLinks: [{ icon: "github", link: "https://github.com/janasco/jkbmsr" }],
  },
});
