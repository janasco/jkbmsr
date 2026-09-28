import { defineConfig } from "vitepress";

/**
 * The published path, supplied at BUILD time rather than written here.
 *
 * ONE SOURCE, TWO PLACES, AND ONE BUILD CANNOT SERVE BOTH. These files are
 * published twice:
 *
 *   - the apex, at `https://jkbmsr.com/docs/` — staged by
 *     `scripts/stage-docs-at-apex.sh` into the marketing site's Pages output,
 *     so every URL the build emits must be prefixed `/docs/`;
 *   - the subdomain, at `https://docs.jkbmsr.com/` — deployed by
 *     `scripts/deploy-docs.sh`, where the same files are served at the ROOT and
 *     every URL must be prefixed `/`.
 *
 * A static host cannot serve one build at both a root and a sub-path, so `base`
 * is read from the environment and **defaults to `/`**.
 *
 * Baking in `/docs/` looks like the obvious fix and is the opposite of one. It
 * makes the subdomain deployment reference `/docs/assets/…` on a host that has
 * no `/docs/` prefix, so every stylesheet, the theme, the fonts and the icons
 * 404 there — behind a build that reports success and a site that answers 200 on
 * every page. That is the same shape as the icon bug described further down, and
 * it was caught here by staging `docs/dist` and reading where its asset URLs
 * actually point.
 *
 * So the default is the one that leaves `docs.jkbmsr.com` byte-identical to what
 * it serves today, and the apex path is opted into explicitly:
 * `scripts/stage-docs-at-apex.sh` exports `DOCS_BASE=/docs/` and refuses to run
 * with any other value. If it is ever forgotten the build still succeeds, and
 * `stage-docs.mjs` then REFUSES on the root-absolute references that escape
 * `/docs/` — 1,704 of them, measured. The failure is loud, which is why the
 * reference check exists rather than the variable being trusted.
 */
const BASE = process.env.DOCS_BASE ?? '/';
if (!BASE.startsWith('/') || !BASE.endsWith('/')) {
  throw new Error(`DOCS_BASE must begin and end with "/", got ${JSON.stringify(BASE)}`);
}

export default defineConfig({
  title: "JK BMS Remote Docs",
  description: "Documentation for JK BMS Remote, an independent remote monitoring solution for JK-BMS products.",
  base: BASE,
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
  // Every href here must name a file that exists in `docs/docs/public/`, which
  // is the directory VitePress copies into the build output.
  //
  // It was NOT `.vitepress/public/`, which is where these files sat until
  // 2026-09-28. VitePress copies `path.resolve(srcDir, "public")` and nothing
  // else — `srcDir` is the directory passed to the CLI, here `docs`. So the
  // assets sat in a directory the build never reads, were silently absent from
  // every build, and each of the URLs below 404'd in production while the
  // declarations that named them looked perfectly correct. Nothing in the build
  // fails on a missing static asset, so the omission was invisible: the build
  // reported success and the site reported success.
  //
  // Each href is `${BASE}…`, not a literal. VitePress emits `head` entries
  // VERBATIM — it does not prepend `base` to them — so under the apex build
  // (BASE=/docs/) a literal `/favicon.svg` would resolve to the marketing site's
  // homepage, and under the subdomain build (BASE=/) the same literal is correct.
  // Interpolating the one variable keeps both right, and keeps them right for
  // the same reason rather than by coincidence.
  //
  // `sizes` is the measured pixel size of the file it names, not the name. The
  // apple-touch-icon used to point at a 1024x1024 store icon, which is not what
  // iOS wants; it now points at a real 180x180. Both are declared so a
  // high-density device gets the large one. This mirrors the icon block already
  // corrected on web-app and admin — same files, same bytes, same sizes.
  // ONE canonical URL, declared by BOTH deployments.
  //
  // Serving the same pages at `docs.jkbmsr.com` and at `jkbmsr.com/docs/` makes
  // them byte-for-byte identical, and two identical pages with no canonical is
  // the worst of both worlds: a search engine has to guess, and the guess is
  // whichever one it crawled first. So the canonical is the apex path, and it is
  // emitted here rather than at deploy time so that the subdomain build and the
  // apex build cannot disagree — the subdomain canonicalises onward on its own,
  // with no DNS change and no redirect.
  //
  // Deliberately NOT derived from BASE. Deriving it would give the subdomain a
  // self-referencing canonical and the apex one as well, which is two canonicals
  // for one body of content — the exact thing this is here to prevent. The
  // canonical is a constant decision about which URL is the real one; BASE is a
  // deployment detail about where the assets happen to be rooted.
  transformHead({ page }: { page: string }) {
    // `page` is the SOURCE-relative path -- `api/authentication.md`, not the
    // served URL. My first attempt stripped `.html`, which produced canonicals
    // like https://jkbmsr.com/docs/api/authentication.md: a URL that does not
    // exist, pointing at a page that does. And my check for it tested only for
    // a literal ".html" and for the apex prefix, both of which a `.md` path
    // passes -- so the assertion confirmed the bug rather than catching it.
    //
    // This mirrors what VitePress itself does under `cleanUrls`: `index.md`
    // collapses to the directory, and any other `.md` loses the extension.
    const rel = page
      .replace(/(^|\/)index\.md$/, "$1")
      .replace(/\.md$/, "")
      .replace(/^\/+|\/+$/g, "");
    // A 404 page has no canonical: it is not content, and pointing one at a
    // supposed canonical URL tells a crawler that URL is the real version of a
    // page that does not exist.
    if (rel === "404" || rel === "") return [];
    return [["link", { rel: "canonical", href: `https://jkbmsr.com/docs/${rel}` }]];
  },
  head: [
    [
      "link",
      { rel: "icon", type: "image/svg+xml", href: `${BASE}favicon.svg` },
    ],
    [
      "link",
      { rel: "icon", type: "image/png", sizes: "64x64", href: `${BASE}favicon.png` },
    ],
    [
      "link",
      { rel: "apple-touch-icon", sizes: "180x180", href: `${BASE}apple-touch-icon.png` },
    ],
    [
      "link",
      { rel: "apple-touch-icon", sizes: "1024x1024", href: `${BASE}logos/app-icon-1024.png` },
    ],
    [
      "script",
      {},
      "try{var k='vitepress-theme-appearance';if(!localStorage.getItem(k)){localStorage.setItem(k,'light');document.documentElement.classList.remove('dark');}}catch(e){}",
    ],
  ],
  themeConfig: {
    // DELIBERATELY NOT `${BASE}favicon.svg` — do not "fix" this.
    //
    // `head` and `themeConfig.logo` are handled differently by VitePress, and
    // the difference is invisible in the output if you only read one of them:
    //
    //   - `head` is emitted VERBATIM. `resolveSiteDataHead()` in
    //     vitepress/dist/node returns `userConfig?.head ?? []` and pushes onto
    //     it; nothing in that path prepends `base`. Which is why the four icon
    //     hrefs above interpolate BASE and this one does not.
    //   - `themeConfig.logo` is rendered through `VPImage.vue`, which calls
    //     `withBase()` on it explicitly. A literal `/favicon.svg` correctly
    //     becomes `/docs/favicon.svg` under the apex build and `/favicon.svg`
    //     under the subdomain build, with no interpolation needed.
    //
    // Writing `${BASE}` here was tried and produced `/docs/docs/favicon.svg`,
    // because base is applied twice. It was caught by the resolution check in
    // stage-docs.mjs — a file-EXISTENCE check, not a prefix check, since
    // `/docs/docs/favicon.svg` is *under* `/docs/` and a prefix assertion would
    // have passed it. The prefix check is necessary but not sufficient, which is
    // why that script does both.
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
