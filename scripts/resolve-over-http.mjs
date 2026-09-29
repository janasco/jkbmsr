#!/usr/bin/env node
/**
 * resolve-over-http.mjs — request every URL the docs pages reference, and report
 * the STATUS the server gives it.
 *
 * WHY THIS EXISTS ALONGSIDE THE FILE-EXISTENCE CHECK IN stage-docs.mjs
 *   The existence check answers "is the file in the tree that will be uploaded".
 *   That is the right question about a build directory and the wrong one about a
 *   site: the docs icons sat in `docs/docs/.vitepress/public/` — a directory
 *   VitePress never reads — and were absent from every build and 404ing in
 *   production, behind a build that reported success and a site that reported 200
 *   on every page. A file existing in `dist/` is not evidence that anything
 *   serves it.
 *
 *   So this asks the serving layer instead. Point it at a preview before
 *   publishing, and at the live apex afterwards:
 *
 *     node scripts/resolve-over-http.mjs http://localhost:4321
 *     node scripts/resolve-over-http.mjs https://jkbmsr.com --docs-only
 *
 *   Redirects are NOT followed silently. A 3xx is reported as a 3xx, with its
 *   Location, because a link that works only after a redirect is a different
 *   thing from a link that works, and `urllib.request.urlopen` following
 *   redirects has reported 200 in this project for two URLs that were genuinely
 *   301 — a measurement that landed on the destination and answered the opposite
 *   question without announcing it.
 *
 * Exit: 0 every reference resolved, 1 at least one did not, 2 could not run.
 */
import process from 'node:process';
import { extractHtmlRefs, extractCssRefs, BASE } from './stage-docs.mjs';

const argv = process.argv.slice(2);
let base = null;
let docsOnly = false;
let followRedirects = false;
for (let i = 0; i < argv.length; i += 1) {
  if (argv[i] === '--docs-only') docsOnly = true;
  else if (argv[i] === '--follow') followRedirects = true;
  else if (!argv[i].startsWith('--')) base = argv[i];
}
if (!base) {
  process.stdout.write('usage: resolve-over-http.mjs <base-url> [--docs-only] [--follow]\n');
  process.exit(2);
}
base = base.replace(/\/+$/, '');

/**
 * `astro preview` binds IPv6 `[::1]` ONLY, and `fetch` resolves `localhost` to
 * 127.0.0.1 often enough to matter — the first version of this script died with
 * a bare `ECONNREFUSED 127.0.0.1:4321` and a stack trace, which reads as "the
 * preview is not running" when it is running and listening on the other family.
 * The same trap is on record for anyone driving this host by hand. So: retry a
 * localhost base over `[::1]`, and say which one answered.
 */
let familyNote = '';
async function get(pathOrUrl, init = {}) {
  // Accepts a path relative to `base` or an absolute URL, because the crawl
  // queues absolute URLs while the reference scan deals in root-absolute paths.
  // Conflating the two is how the first version produced
  // "http://localhost:4321http://localhost:4321/docs/".
  const target = /^https?:\/\//i.test(pathOrUrl) ? pathOrUrl : `${base}${pathOrUrl}`;
  try {
    return await fetch(target, init);
  } catch (e) {
    const refused = /ECONNREFUSED|ECONNRESET|ENOTFOUND/.test(String(e && e.cause ? `${e} ${e.cause.code}` : e));
    if (refused && /^(http:\/\/)?localhost(:|\/|$)/.test(base)) {
      const swapped = base.replace(/^(http:\/\/)?localhost/, '[::1]');
      familyNote = `(${base} refused; retried over [::1] — astro preview binds IPv6 [::1] only)`;
      base = swapped;
      return fetch(/^https?:\/\//i.test(pathOrUrl) ? pathOrUrl.replace(/^(https?:\/\/)localhost/, '$1[::1]') : `${base}${pathOrUrl}`, init);
    }
    throw e;
  }
}

/** A URL is a PAGE candidate if it ends in `/`, ends in `.html`, or has no file
 * extension at all. Everything else is an asset.
 *
 * This distinction is the whole reason the crawl reports a page count at all.
 * The first version followed every `/docs/…` href into the fetch queue and then
 * parsed each response as HTML, so `assets/app.js` was counted as a page and the
 * run cheerfully reported "crawled 94 pages" for a build that has 35 HTML files.
 * A count is only a count of the thing counted, and "94 pages" is the exact
 * shape of confident wrong number this project keeps producing.
 */
const isPageUrl = (u) => {
  const p = new URL(u).pathname;
  return p.endsWith('/') || p.endsWith('.html') || !/\.[a-z0-9]+$/i.test(p);
};

/** The docs page set, from the site itself rather than from a list. */
async function discoverDocsPages() {
  const out = [];
  const seen = new Set();
  const queue = [`${base}${BASE}`];
  while (queue.length) {
    const url = queue.shift();
    if (seen.has(url)) continue;
    seen.add(url);
    const res = await get(url, { redirect: 'follow' });
    if (!res.ok) {
      process.stdout.write(`   FAIL  ${res.status} ${url}\n`);
      process.exit(1);
    }
    // `res.url` is where the SERVER says this page lives after its own
    // canonicalisation — `/docs/api/index` becomes `/docs/api/`. Recording the
    // requested spelling instead makes the same page look like two, and the
    // first version of the orphan check below reported two pages as unreachable
    // that are the two most linked pages in the site. The server's answer to
    // "what is this page's URL" beats string-munging between two spellings.
    out.push({ url, finalUrl: res.url, html: await res.text() });
    // Follow same-base /docs/ links, so a page nobody remembered to list is
    // still checked. A sitemap is a list; this is a crawl.
    for (const { url: href } of extractHtmlRefs(out[out.length - 1].html)) {
      if (!href.startsWith(BASE)) continue;
      const abs = new URL(href, url).href;
      if (isPageUrl(abs) && !seen.has(abs)) queue.push(abs);
    }
  }
  return out;
}

async function statusOf(pathAndQuery) {
  const res = await get(pathAndQuery, { redirect: followRedirects ? 'follow' : 'manual' });
  return { status: res.status, type: res.headers.get('content-type') || '', location: res.headers.get('location') || '' };
}

const pages = await discoverDocsPages();
if (pages.length < 5) {
  process.stdout.write(`   FAIL  crawled only ${pages.length} page(s) from ${base}${BASE}, so this run would be a near-empty sample\n`);
  process.exit(1);
}
const knownPages = new Set(pages.map((p) => new URL(p.finalUrl).pathname));
const requestedPages = new Set(pages.map((p) => new URL(p.url).pathname));
process.stdout.write(`   ok    crawled ${pages.length} page(s) from ${base}${BASE} by link, not from a list${familyNote ? ` ${familyNote}` : ''}\n`);
if (knownPages.has(`${BASE}404.html`)) {
  process.stdout.write('   FAIL  404.html was crawled as a page; it is a status, not a destination\n');
  process.exit(1);
}
process.stdout.write(
  `   ..    404.html is correctly NOT among them. The build's own file count is the other tool's number to\n` +
    `         compare against — stage-docs.mjs reports it, and it also generates the sitemap from it.\n`
);

/**
 * Pages in the build that no other page links to.
 *
 * A crawl cannot find these — that is the definition — so asking "did the crawl
 * reach every page?" is unanswerable from the crawl. The count is reported
 * because it is the difference between "34 pages exist" and "34 pages exist and
 * 33 of them can be reached by clicking", and only one of those is a claim about
 * the site. The derived sitemap DOES list the orphan, because it is built from
 * the file list rather than from links, which is the right source for a sitemap
 * and the wrong one for a claim about navigation.
 */
const sitemapText = await (await get(`${BASE}sitemap.xml`)).text();
const inSitemap = new Set([...sitemapText.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => new URL(m[1]).pathname));
const orphans = [...inSitemap].filter((p) => !knownPages.has(p));
const canonicalisations = [...requestedPages].filter((p) => !knownPages.has(p));
process.stdout.write(
  `\n   sitemap lists ${inSitemap.size} URL(s); the crawl reached ${[...inSitemap].filter((p) => knownPages.has(p)).length} of them.\n`
);
if (canonicalisations.length) {
  process.stdout.write(
    `   ..    ${canonicalisations.length} link(s) point at a spelling the server redirects: ${canonicalisations.map((p) => `${p} -> ${pages.find((x) => new URL(x.url).pathname === p).finalUrl.replace(base, '')}`).join(', ')}\n` +
      `         Each is a working link with one extra hop. Reported, not fixed: these come from VitePress's own\n` +
      `         \`link: "/api/index"\` sidebar entries, and rewording them to a trailing slash would change what\n` +
      `         the jkbmsr-docs origin serves on its next deploy, which is out of scope here.\n`
  );
}
if (orphans.length) {
  process.stdout.write(
    `   ..    ${orphans.length} page(s) are in the sitemap but not reachable by any link from a crawled page:\n` +
      orphans.map((o) => `           ${o}`).join('\n') +
      `\n         A crawler will find them; a person clicking will not. Not a defect in this merge and not\n` +
      `         something to fix here — recorded because "N pages exist" and "N pages are reachable" are\n` +
      `         different claims and only the first was on record.\n`
  );
} else {
  process.stdout.write('   ok    every URL in the sitemap is reachable by an internal link\n');
}

const refs = new Map(); // path -> Set of "page (via attr)"
for (const { url, html } of pages) {
  for (const { url: href, via } of extractHtmlRefs(html)) {
    if (!href.startsWith('/')) continue; // relative, external, data:, fragment
    if (docsOnly && !href.startsWith(BASE)) continue;
    if (!refs.has(href)) refs.set(href, new Set());
    refs.get(href).add(`${new URL(url).pathname} (${via})`);
  }
}
// The stylesheet's own url()s, which is where the fonts live and where an
// HTML-only scan finds nothing.
const cssRefs = [];
for (const { url, html } of pages) {
  for (const m of html.matchAll(/<link[^>]+rel="[^"]*stylesheet[^"]*"[^>]+href="([^"]+)"/g)) {
    if (!m[1].startsWith('/')) continue;
    const res = await get(m[1]);
    if (!res.ok) continue;
    const css = await res.text();
    for (const { url: u } of extractCssRefs(css)) {
      if (u.startsWith('/')) cssRefs.push({ from: m[1], u });
    }
  }
}
for (const { from, u } of cssRefs) {
  if (!refs.has(u)) refs.set(u, new Set());
  refs.get(u).add(`${from} (css url())`);
}

if (refs.size === 0) {
  process.stdout.write('   FAIL  extracted 0 references from the served pages. That is a failure of this script, not a clean result.\n');
  process.exit(1);
}

const results = [];
for (const p of [...refs.keys()].sort()) results.push({ p, ...(await statusOf(p)) });

const ok = results.filter((r) => r.status === 200);
const redirects = results.filter((r) => r.status >= 300 && r.status < 400);
const missing = results.filter((r) => r.status === 404);
const other = results.filter((r) => r.status !== 200 && !(r.status >= 300 && r.status < 400) && r.status !== 404);

process.stdout.write(`\n   ${refs.size} distinct reference(s) requested from ${base}\n`);
process.stdout.write(`     ${ok.length} answered 200\n`);
process.stdout.write(`     ${redirects.length} answered 3xx (NOT followed — a link that only works via a redirect is reported, not hidden)\n`);
process.stdout.write(`     ${missing.length} answered 404\n`);
process.stdout.write(`     ${other.length} answered something else\n\n`);
for (const r of redirects) process.stdout.write(`   3xx   ${r.status} ${r.p}  ->  ${r.location}\n`);
for (const r of missing) process.stdout.write(`   404   ${r.p}   referenced by: ${[...refs.get(r.p)].slice(0, 3).join(', ')}\n`);
for (const r of other) process.stdout.write(`   ${r.status}   ${r.p}\n`);

// The four icons, named explicitly, because they were 404ing for the site's whole
// life once already and a merge is exactly where that would come back.
const ICONS = [`${BASE}favicon.svg`, `${BASE}favicon.png`, `${BASE}apple-touch-icon.png`, `${BASE}logos/app-icon-1024.png`];
process.stdout.write('\n   the four docs icons, each requested directly:\n');
let iconsOk = 0;
for (const icon of ICONS) {
  const r = await statusOf(icon);
  const known = results.find((x) => x.p === icon);
  if (r.status === 200) iconsOk += 1;
  process.stdout.write(`     ${r.status === 200 ? 'ok  ' : 'FAIL'}  ${r.status}  ${r.type.padEnd(24)} ${icon}\n`);
  void known;
}

if (missing.length || other.length || iconsOk !== ICONS.length) {
  process.stdout.write('\nVERDICT: FAILED — the served output does not match what the pages reference.\n');
  process.exit(1);
}
process.stdout.write('\nVERDICT: every referenced URL answers 200 from the server, including all 4 icons.\n');
if (redirects.length) {
  process.stdout.write(`         ${redirects.length} redirect(s) are reported above rather than followed; each is a link that works, but not directly.\n`);
}
process.exit(0);
