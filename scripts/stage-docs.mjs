#!/usr/bin/env node
/**
 * stage-docs.mjs — compose the VitePress docs build into the marketing site's
 * Cloudflare Pages output, and prove the composition is correct.
 *
 * WHY A SCRIPT AND NOT A LINE IN DEPLOY.md
 *   The two builds live in different repositories (`jkbmsr` holds the docs,
 *   `jkbmsr-site` holds the marketing site) and in different directories, and
 *   the marketing build *empties* `dist/client` on every run. So the order is
 *   load-bearing and invisible: stage before `astro build` and the output is
 *   deleted; stage after it and it ships. That is a rule a human has to
 *   remember, which is the same shape of mistake as the docs icons that sat in
 *   `.vitepress/public/` and 404'd for the site's entire life behind a green
 *   build. Hence a script, so the order is a fact about a file rather than a
 *   memory, and so the verification runs every time rather than when remembered.
 *
 * WHAT IT DOES, IN ORDER
 *   1. validate both inputs, and refuse a docs build that carries its own
 *      `_headers` or `_redirects` (see PHASE 7 for why that is fatal, not tidy)
 *   2. refuse to stage over anything the apex already serves
 *   3. copy, then compare the copy by sha256 — a copy that has not been
 *      compared is not a copy
 *   4. make the staged HTML satisfy the apex's Content-Security-Policy
 *   5. generate /docs/sitemap.xml from the build, not from a list
 *   6. resolve every local URL in the staged HTML and every `url()` in the
 *      staged CSS, against the MERGED output
 *   7. account for every header and redirect rule the apex ships, and say which
 *      ones reach /docs/
 *   8. prove the 321 apex files are byte-identical afterwards
 *
 * IT DEPLOYS NOTHING. There is no Cloudflare write in this file. The publish
 * step is a separate, explicitly-typed command in DEPLOY.md.
 *
 * Exit status: 0 = staged and every assertion held, 1 = refused, 2 = could not
 * run (a missing or unreadable input is not the same verdict as a wrong one).
 */
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(SCRIPT_DIR, '..');

/** The published path. Must equal `BASE` in docs/docs/.vitepress/config.ts. */
export const BASE = '/docs/';
/** Origin the docs are published under. Asserted, not derived from the host. */
export const SITE_ORIGIN = 'https://jkbmsr.com';
/** The directory the docs are staged into, relative to the Pages upload root. */
const DOCS_DIR_NAME = 'docs';
/**
 * The marker lives in the apex's `dist/`, NOT in `dist/client/`.
 *
 * Anything inside the Pages upload root is published. A marker inside it would
 * be a public file at `/_stage-manifest.json` naming absolute paths on this
 * host, and — worse — it would make the safe-deletion test depend on a file
 * that a deploy could serve. `dist/` is the parent of the upload root, so it is
 * never uploaded and `astro build` does not clear it.
 */
const markerFile = (apexDist) => path.join(path.dirname(apexDist), '.stage-docs-at-apex.json');

// ─────────────────────────────────────────────────────────────── reporting ────

const RED = process.stderr.isTTY ? (s) => `\x1b[31m${s}\x1b[0m` : (s) => s;
const GRN = process.stderr.isTTY ? (s) => `\x1b[32m${s}\x1b[0m` : (s) => s;
const YEL = process.stderr.isTTY ? (s) => `\x1b[33m${s}\x1b[0m` : (s) => s;

let phase = 0;
let problems = 0;
let warnings = 0;
const summary = { phases: [], staged: 0, refsChecked: 0, apexFilesChecked: 0 };

function head(n, title) {
  phase = n;
  process.stdout.write(`\n${'='.repeat(72)}\nPHASE ${n} — ${title}\n${'='.repeat(72)}\n`);
}
function ok(msg) {
  process.stdout.write(`   ok    ${msg}\n`);
}
function info(msg) {
  process.stdout.write(`   ..    ${msg}\n`);
}
function warn(msg) {
  warnings += 1;
  process.stdout.write(`   ${YEL('WARN')}  ${msg}\n`);
}
function bad(msg) {
  problems += 1;
  process.stdout.write(`   ${RED('FAIL')}  ${msg}\n`);
}

/** A hard stop. Anything past this line would be reasoning about a broken input. */
class Refuse extends Error {
  constructor(code, msg) {
    super(msg);
    this.code = code;
  }
}
const refuse = (code, msg) => {
  throw new Refuse(code, msg);
};

// ────────────────────────────────────────────────────────────────── helpers ────

const sha256 = (buf) => createHash('sha256').update(buf).digest('hex');

/** Every file under `dir`, as paths relative to `dir`, sorted. */
export function walk(dir, base = dir, acc = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const abs = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(abs, base, acc);
    else if (entry.isFile()) acc.push(path.relative(base, abs));
  }
  return acc;
}

const isDir = (p) => {
  try {
    return fs.statSync(p).isDirectory();
  } catch {
    return false;
  }
};
const isFile = (p) => {
  try {
    return fs.statSync(p).isFile();
  } catch {
    return false;
  }
};

/** `{rel: sha256hex}` for every file under `dir`. */
export function manifest(dir) {
  const out = {};
  for (const rel of walk(dir)) out[rel] = sha256(fs.readFileSync(path.join(dir, rel)));
  return out;
}

// ───────────────────────────────────────────── the URL extractor, and its test ───

/**
 * Every URL-bearing reference in one HTML document.
 *
 * Deliberately wider than `href`/`src`: the class of bug this script exists to
 * catch has repeatedly been an attribute nobody thought to look at. An
 * `og:image` in a `content=` attribute and a font in a stylesheet's `url()`
 * are the same failure as a stylesheet in a `src=`. An audit check in this
 * project's history was named for scanning for Google Fonts, read HTML only, and
 * so passed a `@import` living in a stylesheet — the same miss, opposite
 * direction: the thing nobody thought to look at.
 *
 * Returns `[{url, via}]`. Ordering is stable, duplicates are preserved (a page
 * that references the same asset from <head> and from a component is two
 * references and both are counted).
 */
export function extractHtmlRefs(html) {
  const refs = [];
  const ATTRS = ['href', 'src', 'action', 'poster', 'data-src', 'formaction', 'cite'];
  for (const a of ATTRS) {
    // Double-quoted and single-quoted, so a hand-edited attribute is still seen.
    const re = new RegExp(`\\b${a}\\s*=\\s*("([^"]*)"|'([^']*)')`, 'gi');
    for (const m of html.matchAll(re)) refs.push({ url: m[2] ?? m[3] ?? '', via: a });
  }
  for (const m of html.matchAll(/\bsrcset\s*=\s*"([^"]*)"/gi)) {
    for (const cand of m[1].split(',')) {
      const u = cand.trim().split(/\s+/)[0];
      if (u) refs.push({ url: u, via: 'srcset' });
    }
  }
  // <meta property="og:image" content="…"> and the twitter: variants.
  for (const m of html.matchAll(
    /<meta[^>]+(?:property|name)\s*=\s*"(og:[a-z:]+|twitter:[a-z:]+)"[^>]*content\s*=\s*"([^"]*)"/gi
  )) {
    refs.push({ url: m[2], via: `meta:${m[1]}` });
  }
  // A CSS `url()` can appear inline in a <style> block or a style attribute.
  for (const m of html.matchAll(/url\(\s*(?:"([^"]*)"|'([^']*)'|([^)'"]*))\s*\)/gi)) {
    refs.push({ url: m[1] ?? m[2] ?? m[3] ?? '', via: 'css-url' });
  }
  return refs.filter((r) => r.url.trim() !== '');
}

/** Every `url()` in a stylesheet. Same reason as above: the HTML-only blind spot. */
export function extractCssRefs(css) {
  const refs = [];
  for (const m of css.matchAll(/url\(\s*(?:"([^"]*)"|'([^']*)'|([^)'"]*))\s*\)/gi)) {
    refs.push({ url: m[1] ?? m[2] ?? m[3] ?? '', via: 'css-url' });
  }
  return refs.filter((r) => r.url.trim() !== '');
}

/**
 * The URL extractor's self-test, parameterised on the extractor so a test can
 * hand it a deliberately broken one and REQUIRE it to fail. A guard that has
 * never been seen to reject anything is not known to work, and this project's
 * record is three separate instances of a check reporting zero for a subject
 * that was fine.
 */
export function runExtractorSelfTest(extractHtml = extractHtmlRefs, extractCss = extractCssRefs) {
  const CASES = [
    {
      name: 'plain attributes',
      html: '<a href="/docs/a.html">x</a><img src=\'/docs/i.png\'><form action="/docs/s"></form>',
      expect: ['/docs/a.html', '/docs/i.png', '/docs/s'],
    },
    {
      name: 'srcset with descriptors',
      html: '<img srcset="/docs/a.png 1x, /docs/b.png 2x">',
      expect: ['/docs/a.png', '/docs/b.png'],
    },
    {
      name: 'og:image in content=',
      html: '<meta property="og:image" content="/docs/og.png"><meta name="twitter:image" content="https://x.example/t.png">',
      expect: ['/docs/og.png', 'https://x.example/t.png'],
    },
    {
      name: 'inline style and <style> url()',
      html: '<div style="background:url(/docs/bg.png)"></div><style>.a{background:url("/docs/c.png")}</style>',
      expect: ['/docs/bg.png', '/docs/c.png'],
    },
    {
      name: 'data: and fragment are seen, not silently dropped',
      html: '<img src="data:image/svg+xml,%3Csvg%3E"><a href="#top">t</a>',
      expect: ['data:image/svg+xml,%3Csvg%3E', '#top'],
    },
  ];

  const failures = [];
  for (const c of CASES) {
    const got = extractHtml(c.html).map((r) => r.url);
    for (const want of c.expect) {
      if (!got.includes(want)) {
        failures.push(`${c.name}: expected to extract ${JSON.stringify(want)}, got ${JSON.stringify(got)}`);
      }
    }
  }
  const cssGot = extractCss('@font-face{src:url(/docs/f.woff2) format("woff2")}').map((r) => r.url);
  if (!cssGot.includes('/docs/f.woff2')) failures.push(`css: expected /docs/f.woff2, got ${JSON.stringify(cssGot)}`);
  // The vacuous case, named as such: an empty document must extract nothing,
  // and that must be a distinguishable state, not a silent pass.
  if (extractHtml('').length !== 0) failures.push('empty document extracted references');

  if (failures.length) {
    throw new Error(
      `the URL extractor failed its own self-test, so every resolution count would be meaningless:\n     - ${failures.join('\n     - ')}`
    );
  }
  return CASES.length + 1;
}

/** Run the self-test on the real extractors, and turn a failure into a refusal. */
function selfTest() {
  try {
    return runExtractorSelfTest();
  } catch (e) {
    refuse(1, e.message);
  }
}

// ───────────────────────────────────────── Pages `_headers` / `_redirects` ─────

/**
 * Glob for a Pages `_headers` / `_redirects` source pattern.
 *
 * `*` is a splat and DOES cross `/` — measured, not assumed: the live apex
 * serves `Cache-Control: public, max-age=604800` on
 * `/assets/img/ble-shots/01-status-live.jpg`, a three-segment path, and the
 * only rule that could supply that value is `/assets/*`. A three-segment match
 * is the positive control; had `*` been confined to one segment that header
 * would be absent. `:name` placeholders match a single segment.
 */
export function pagesGlobToRegExp(source) {
  let out = '';
  for (let i = 0; i < source.length; i += 1) {
    const ch = source[i];
    if (ch === '*') {
      out += '.*';
    } else if (ch === ':') {
      // Step PAST the colon before consuming the name. The first version tested
      // `source[i]` while still pointing at `:`, so the name was never consumed
      // and `/x/:id` compiled to `/x/[^/]+:id` — a rule that then failed to
      // match the very thing it describes. Found by stage-docs.test.mjs, which
      // asserts `:name` matches exactly one segment. No rule in the apex's own
      // _headers or _redirects uses a placeholder, so this was latent rather
      // than live, and it would have been reported as "no rule shadows /docs/"
      // by a check that was silently unable to see a placeholder rule at all.
      i += 1;
      while (i < source.length && /[A-Za-z0-9_]/.test(source[i])) i += 1;
      i -= 1;
      out += '[^/]+';
    } else {
      out += ch.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    }
  }
  return new RegExp(`^${out}$`);
}

/** Parse a Pages `_headers` file into `[{source, headers:{name:value}}]`. */
export function parseHeaders(text) {
  const rules = [];
  let current = null;
  for (const raw of text.split('\n')) {
    if (!raw.trim() || raw.trim().startsWith('#')) continue;
    if (!/^\s/.test(raw)) {
      current = { source: raw.trim(), headers: [] };
      rules.push(current);
    } else if (current) {
      const idx = raw.indexOf(':');
      if (idx > 0) current.headers.push([raw.slice(0, idx).trim().toLowerCase(), raw.slice(idx + 1).trim()]);
    }
  }
  return rules;
}

/** Parse a Pages `_redirects` file into `[{source, target, status}]`. */
export function parseRedirects(text) {
  return text
    .split('\n')
    .map((l) => l.replace(/#.*$/, '').trim())
    .filter((l) => l !== '')
    .map((l) => {
      const [source, target, status] = l.split(/\s+/);
      return { source, target, status: Number(status) || 301 };
    });
}

/**
 * The header a set of Pages rules would produce for one path.
 *
 * Pages APPENDS every matching rule's value for a given header rather than
 * picking the most specific match. That has shipped in this project, as
 *     content-type: application/atom+xml; charset=utf-8, application/rss+xml; charset=utf-8
 * — two comma-separated media types in one field, which RFC 7231 does not
 * permit, and it was invisible in the build directory because `dist/` was
 * correct and only the edge was wrong. So the question is not "which rule
 * wins" but "is this header set by more than one rule", and that is what this
 * returns.
 */
export function headersFor(rules, urlPath) {
  const applied = new Map();
  for (const rule of rules) {
    if (!pagesGlobToRegExp(rule.source).test(urlPath)) continue;
    for (const [name, value] of rule.headers) {
      if (!applied.has(name)) applied.set(name, []);
      applied.get(name).push({ source: rule.source, value });
    }
  }
  return applied;
}

/**
 * Concrete paths a Pages source pattern matches, for overlap testing.
 *
 * Overlap cannot be decided by comparing two globs in general, so it is decided
 * by generating paths from one rule and testing them against the other. Each
 * `*` is expanded three ways — empty, one segment, and a NESTED path — because
 * the case that matters here is exactly the nested one: `/*` and `/docs/*` look
 * unrelated as strings and overlap on every docs URL, and a probe set without a
 * nested expansion would call them disjoint and report zero.
 */
export function probePathsFor(source, limit = 16) {
  const expansions = ['', 'x', 'x/y'];
  let out = [''];
  for (const ch of source) {
    if (ch === '*') out = out.flatMap((p) => expansions.map((e) => p + e));
    else if (ch === ':') out = out.map((p) => `${p}x`);
    else out = out.map((p) => p + ch);
  }
  return [...new Set(out.filter((p) => p.startsWith('/')))].slice(0, limit);
}

/**
 * Every (header, pair-of-rules) combination whose source patterns overlap — that
 * is, every case where Pages' append semantics would put two values in one field.
 *
 * EXHAUSTIVE over rule pairs, not sampled over paths. The first version of this
 * check tested eight hand-picked `/docs/…` paths, which is the same shape of
 * weakness as the audit checks that sample a handful of URLs and call the result
 * coverage: a rule that overlaps only on a path nobody thought to list is
 * invisible, and the file still reports zero. The finding here is about the RULE
 * SET, not about any particular URL, so it is decided on the rules.
 */
export function overlappingHeaderRules(rules) {
  const out = [];
  for (let i = 0; i < rules.length; i += 1) {
    for (let j = i + 1; j < rules.length; j += 1) {
      const a = rules[i];
      const b = rules[j];
      const names = new Set([...a.headers, ...b.headers].map(([n]) => n));
      for (const name of names) {
        if (!a.headers.some(([n]) => n === name)) continue;
        if (!b.headers.some(([n]) => n === name)) continue;
        // Expand probes from BOTH rules and test each against the other.
        // One direction is not enough, and the direction that fails is the
        // dangerous one: expanding `/*` yields `/`, `/x`, `/x/y`, none of which
        // match `/docs/*`, so a one-directional test declares the broadest rule
        // in the file disjoint from every narrower one — including from itself,
        // in the sense that the pair `/*` + `/docs/*` reads as clean. Found by
        // stage-docs.test.mjs, whose fixture adds exactly that pair to the real
        // _headers and requires it to be caught.
        const witness =
          probePathsFor(a.source).find((p) => pagesGlobToRegExp(b.source).test(p)) ??
          probePathsFor(b.source).find((p) => pagesGlobToRegExp(a.source).test(p));
        if (witness) out.push({ header: name, a: a.source, b: b.source, witness });
      }
    }
  }
  return out;
}

// ────────────────────────────────────────────────────────────── CSP analysis ───

/**
 * Directives of the apex CSP that the staged docs HTML would trip.
 *
 * This exists to make a finding executable instead of a sentence in a
 * document that decays. The two that matter were measured on a real build, not
 * reasoned about: 140 inline `<script>` elements (4 per page across 35 pages)
 * against `script-src 'self'`, and 14 `data:` image URLs inside
 * `vp-icons.css` against `img-src 'self'`.
 */
export function analyseCsp(csp, stagedHtmlFiles, stagedCssFiles) {
  const findings = [];
  const checked = stagedHtmlFiles.length + stagedCssFiles.length;
  // Only report against a policy shape we have actually measured against. If
  // the apex ever relaxes this, the right behaviour is to say so and stop
  // reporting — not to keep asserting a violation that no longer applies, and
  // not to fail because the thing we were checking for is no longer there.
  const scriptSrcSelfNoInline =
    /script-src[^;]*'self'/.test(csp) && !/script-src[^;]*'unsafe-inline'/.test(csp) && !/script-src[^;]*'nonce-/.test(csp);
  const styleElemSelf = /style-src-elem[^;]*'self'/.test(csp);
  const attrNone = /script-src-attr[^;]*'none'/.test(csp);
  const dataAllowed =
    /img-src[^;]*data:/.test(csp) || /font-src[^;]*data:/.test(csp) || /style-src[^;]*data:/.test(csp);
  if (!scriptSrcSelfNoInline && !styleElemSelf && !attrNone) {
    return { findings, checked, applicable: false, reason: "the apex CSP no longer has the shape this was measured against" };
  }
  let inlineScripts = 0;
  let dataUrls = 0;
  let inlineStyles = 0;
  let handlers = 0;
  for (const f of stagedHtmlFiles) {
    const h = fs.readFileSync(f, 'utf8');
    inlineScripts += (h.match(/<script(?![^>]*\bsrc\s*=)/g) || []).length;
    inlineStyles += (h.match(/<style[\s>]/g) || []).length;
    handlers += (h.match(/\son[a-z]+\s*=/g) || []).length;
    dataUrls += (h.match(/data:[a-z0-9.+-]+\/[a-z0-9.+-]+;/g) || []).length;
  }
  for (const f of stagedCssFiles) {
    const c = fs.readFileSync(f, 'utf8');
    dataUrls += (c.match(/url\(\s*["']?data:/g) || []).length;
  }
  if (scriptSrcSelfNoInline && inlineScripts) {
    findings.push(
      `script-src 'self' with no 'unsafe-inline' and no nonce: ${inlineScripts} inline <script> element(s) would be refused, so VitePress would not hydrate`
    );
  }
  if (styleElemSelf && inlineStyles) findings.push(`style-src-elem 'self': ${inlineStyles} inline <style> element(s) would be refused`);
  if (attrNone && handlers) findings.push(`script-src-attr 'none': ${handlers} inline event-handler attribute(s) would be refused`);
  if (dataUrls && !dataAllowed) findings.push(`img-src 'self' (no data:): ${dataUrls} data: URL(s) would be refused`);
  return { findings, checked, applicable: true, inlineScripts, dataUrls, inlineStyles, handlers };
}

// ───────────────────────────────────────────────────────────── inline scripts ───

/**
 * Replace every inline `<script>` with a same-origin external one.
 *
 * WHY THIS EXISTS. The apex's `/*` rule reaches `/docs/**` — measured above —
 * and its CSP has no `'unsafe-inline'` and no nonce. VitePress emits four
 * inline scripts per page, one of which (`check-mac-os`) is pushed
 * unconditionally in `resolveSiteDataHead()` with no config switch to suppress
 * it, so the docs cannot be made CSP-clean by configuration. The two ways out
 * are: relax the apex CSP for `/docs/*` (another repository, and it would put a
 * second `'unsafe-inline'` into a file whose own comment says there is exactly
 * one), or move the bytes to a same-origin file, which `script-src 'self'`
 * already permits.
 *
 * This is the second option. It changes the apex's headers not at all, and it
 * runs only on the STAGED copy, so the `jkbmsr-docs` build and
 * `docs.jkbmsr.com` keep the bytes they have today, byte for byte.
 *
 * The `src` is added in place and the body removed, so execution order is
 * unchanged: a classic external script in <head> is parser-blocking exactly
 * where an inline one was, and the end-of-body one still runs before the
 * deferred module in <head>.
 */
function externaliseInlineScripts(dir, htmlRelPaths) {
  const byHash = new Map(); // body -> {hash, rel}
  let total = 0;
  let files = 0;
  for (const rel of htmlRelPaths) {
    const abs = path.join(dir, rel);
    const before = fs.readFileSync(abs, 'utf8');
    if (!/<script(?![^>]*\bsrc\s*=)/.test(before)) continue;
    files += 1;
    const after = before.replace(/<script([^>]*?)>([\s\S]*?)<\/script>/gi, (whole, attrs, body) => {
      if (/\bsrc\s*=/.test(attrs)) return whole;
      if (body.trim() === '') return whole;
      total += 1;
      if (!byHash.has(body)) {
        const h = sha256(body).slice(0, 16);
        byHash.set(body, { hash: h, rel: `assets/inline-${h}.js` });
      }
      return `<script${attrs.replace(/\s+$/, '')} src="${BASE}${byHash.get(body).rel}"></script>`;
    });
    if (after !== before) fs.writeFileSync(abs, after);
  }
  for (const [body, { rel }] of byHash) {
    const abs = path.join(dir, rel);
    fs.mkdirSync(path.dirname(abs), { recursive: true });
    fs.writeFileSync(abs, body);
  }
  return { total, files, unique: byHash.size };
}

// ────────────────────────────────────────────────────────────── the sitemap ─────

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/** `a/b/index.html` -> `/docs/a/b/`, `a/b.html` -> `/docs/a/b`, `index.html` -> `/docs/`. */
export function pageUrlFor(rel) {
  let p = rel;
  if (p === 'index.html') return BASE;
  if (p.endsWith('/index.html')) p = p.slice(0, -'index.html'.length);
  else if (p.endsWith('.html')) p = p.slice(0, -'.html'.length);
  return `${BASE}${p}`;
}

/**
 * A `urlset` for the staged docs, derived from the files that exist.
 *
 * Derived rather than listed, for the reason `src/lib/routes.ts` derives the
 * date archives from `publishedAt`: a hand-written list is a manifest, and a
 * manifest only proves what someone remembered to write down. `/2026/06/`,
 * `/2026/07/` and `/2026/08/` were live 200s that 404ed for the whole life of
 * the cutover because no manifest entry and no redirect had ever mentioned
 * them. A page that exists cannot be left out of this file by forgetting.
 *
 * `404.html` is excluded: it is a static file at a real path, so a sitemap
 * entry for it would point a crawler at a page that is a 404 in intent.
 */
export function buildDocsSitemap(htmlRelPaths) {
  const urls = htmlRelPaths
    .filter((r) => r !== '404.html')
    .map(pageUrlFor)
    .sort();
  const body = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls.map((u) => `  <url><loc>${esc(SITE_ORIGIN + u)}</loc></url>`).join('\n')}
</urlset>
`;
  return { body, urls };
}

/** Minimal, strict-ish XML reader for the two sitemap shapes we produce/consume. */
export function parseSitemap(xml) {
  const kind = /<sitemapindex[\s>]/.test(xml) ? 'index' : /<urlset[\s>]/.test(xml) ? 'urlset' : 'unknown';
  const locs = [...xml.matchAll(/<loc>\s*([^<]*?)\s*<\/loc>/g)].map((m) => m[1]);
  return { kind, locs, wellFormed: /<\?xml[^>]*\?>/.test(xml) && /<\/(?:urlset|sitemapindex)>/.test(xml) };
}

// ──────────────────────────────────────────────────────────────── resolution ───

/**
 * Resolve one referenced URL against the merged output.
 *
 * `siteRoot` is the MERGED tree (`dist/client`), not the docs tree, because the
 * question is not "does the docs build contain it" but "does the thing the
 * browser will ask the edge for exist". A file sitting in the docs output is
 * not evidence; that is exactly the icon bug, and it is why the check is
 * written against the directory that will be uploaded.
 */
export function resolveInMerged(siteRoot, urlPath) {
  const rel = urlPath.replace(/^\//, '');
  const direct = [rel, `${rel}index.html`, `${rel}/index.html`, rel.replace(/\/$/, '') + '.html'];
  for (const c of direct) {
    if (c !== '' && isFile(path.join(siteRoot, c))) return c;
  }
  return null;
}

/** Resolve a relative reference against the URL of the page that carries it. */
function absolutise(pageUrl, ref) {
  const base = new URL(pageUrl, SITE_ORIGIN);
  return new URL(ref, base).pathname;
}

// ──────────────────────────────────────────────────────────────────── main ─────

function parseArgs(argv) {
  const out = {
    apex: process.env.APEX_DIST || '/home/jkbmsr/jkbmsr-site/dist/client',
    docs: process.env.DOCS_DIST || path.join(REPO_ROOT, 'docs', 'docs', '.vitepress', 'dist'),
    checkOnly: false,
    externalise: true,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--apex-dist') out.apex = argv[(i += 1)];
    else if (a === '--docs-dist') out.docs = argv[(i += 1)];
    else if (a === '--check-only') out.checkOnly = true;
    else if (a === '--no-externalise') out.externalise = false;
    else if (a === '-h' || a === '--help') {
      process.stdout.write(
        'usage: stage-docs.mjs [--apex-dist DIR] [--docs-dist DIR] [--check-only] [--no-externalise]\n' +
          '  stages the VitePress build into DIR/docs and verifies the result. Deploys nothing.\n'
      );
      process.exit(0);
    } else refuse(2, `unknown argument: ${a}`);
  }
  return out;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const apexDist = path.resolve(args.apex);
  const docsDist = path.resolve(args.docs);
  const target = path.join(apexDist, DOCS_DIR_NAME);

  // ── PHASE 1 ────────────────────────────────────────────────────────────────
  head(1, 'validate both inputs, and prove the extractor first');
  const selftests = selfTest();
  ok(`URL extractor passed ${selftests} self-tests (a broken extractor would make every count below meaningless)`);

  if (!isDir(apexDist)) refuse(2, `apex Pages output not found: ${apexDist}\n       run \`npm run build\` in the marketing site first — the stage must come AFTER astro build, which empties dist/client.`);
  if (!isDir(docsDist)) refuse(2, `docs build output not found: ${docsDist}\n       run \`cd docs && npm run docs:build\` first.`);

  // Read this script's own marker BEFORE taking any baseline, and subtract what
  // it records. Without that, a second run sees its own first run as 132
  // "collisions" and refuses — the script would work exactly once, which is the
  // difference between a build step and a rumour. It also matters for
  // correctness, not just convenience: a docs-only update changes files inside
  // docs/, and without subtracting them the "the apex is unharmed" check would
  // report our own replacements as the merge having damaged the marketing site.
  const markerPath = markerFile(apexDist);
  let priorMarker = null;
  try {
    priorMarker = JSON.parse(fs.readFileSync(markerPath, 'utf8'));
  } catch {
    priorMarker = null;
  }
  if (priorMarker && priorMarker.base !== BASE) {
    refuse(2, `${markerPath} records base "${priorMarker.base}", this script expects "${BASE}". Refusing rather than guessing which tree it describes.`);
  }
  // CUMULATIVE, not just the last run. `stagedFiles` is what the most recent
  // stage produced; `everStaged` is every path this script has ever put in this
  // tree. The distinction matters because a docs rebuild rehashes every asset, so
  // the previous run's filenames are no longer in `stagedFiles` while still
  // sitting on disk — and with a per-run list they are indistinguishable from a
  // file somebody else put there, which made the run refuse and kept refusing
  // with no way forward. A marker whose job is "which files in this tree are
  // mine" has to answer that cumulatively.
  const priorList = priorMarker
    ? Array.isArray(priorMarker.everStaged)
      ? priorMarker.everStaged
      : Array.isArray(priorMarker.stagedFiles)
        ? priorMarker.stagedFiles
        : []
    : [];
  // Normalise: a marker written before `everStaged` existed holds bare relative
  // paths, a newer one holds apex-relative paths. Accepting both means an
  // upgrade does not orphan the previous run's files — which is precisely the
  // situation that produced the lockout this is fixing.
  const priorStaged = new Set(priorList.map((f) => (f.startsWith(`${DOCS_DIR_NAME}/`) ? f : `${DOCS_DIR_NAME}/${f}`)));

  const apexFull = manifest(apexDist);
  const docsPathExists = Object.keys(apexFull).some((k) => k === DOCS_DIR_NAME || k.startsWith(`${DOCS_DIR_NAME}/`));
  if (docsPathExists && priorStaged.size === 0) {
    refuse(
      1,
      `${apexDist}/docs exists but ${markerPath} records no stage of it, so this script did not put it there.\n` +
        `       Refusing to touch it. If it is stale output, remove it by hand; if it is real, it wins.`
    );
  }
  // The marker and the tree can disagree, and the two ways it happens need
  // different verdicts.
  //
  // A docs rebuild rehashes every asset, so staging a new build over an old one
  // changes the filenames wholesale. Handled by deleting the tree first, which
  // is safe ONLY if every file in it is one this script is responsible for. So
  // the question is not "does the tree match the marker" but "is every file in
  // the tree accounted for by the marker, by the current source build, or by a
  // name this script mints". If yes, the tree is this script's to replace, and
  // the marker mismatch is reported rather than treated as a crisis. If no, some
  // file is there that neither the marketing site nor this script can explain,
  // and deleting it would be deleting somebody else's work.
  //
  // Observed for real on 2026-09-28, and the first version got it wrong twice:
  // it reported "the docs build would overwrite 72 existing apex files" (the
  // symptom, alarming, and about the marketing site when it was not), and then
  // the fix for that message refused to accept its own remedy.
  const docsFiles = walk(docsDist);
  const docsHtmlRel = docsFiles.filter((f) => f.endsWith('.html')).sort();
  if (docsHtmlRel.length === 0) refuse(2, `${docsDist} contains no HTML — a docs build that produced nothing must not be staged`);
  if (docsFiles.length < 20) refuse(2, `${docsDist} contains only ${docsFiles.length} files, which is far below a real VitePress build; refusing to stage a near-empty tree`);
  ok(`docs build: ${docsFiles.length} files, ${docsHtmlRel.length} HTML pages`);

  // A `_headers` or `_redirects` anywhere under the staged tree would be inert:
  // Pages reads ONE of each, at the deployment root. So a docs copy is either
  // dead weight or, worse, a declaration that reads like it is configuring
  // something. Refuse it and say why, rather than shipping a file that does
  // nothing.
  for (const rel of docsFiles) {
    if (path.basename(rel) === '_headers' || path.basename(rel) === '_redirects') {
      refuse(1, `the docs build contains ${rel}.\n       Pages reads exactly one _headers and one _redirects, at the deployment root, so a copy under /docs/ would be silently inert.\n       If the docs genuinely need headers, the rule belongs in the apex _headers under a /docs/* source.`);
    }
  }
  ok('the docs build carries no _headers and no _redirects, so there is nothing to overlap the apex rules');

  // The baseline is the marketing site's own files, with this script's previous
  // output subtracted.
  const apexBefore = Object.fromEntries(Object.entries(apexFull).filter(([k]) => !priorStaged.has(k)));
  const apexCount = Object.keys(apexBefore).length;
  const priorCount = Object.keys(apexFull).length - apexCount;
  if (apexCount === 0) refuse(2, `${apexDist} holds no marketing-site files outside docs/ — nothing to merge into, and a check over it would pass vacuously`);
  for (const required of ['index.html', '_headers', '_redirects', 'robots.txt', 'sitemap.xml']) {
    if (!(required in apexBefore)) refuse(2, `${apexDist} has no ${required}; that does not look like the marketing site's Pages output`);
  }
  ok(
    `apex output: ${apexCount} marketing-site files` +
      (priorCount ? ` (plus ${priorCount} from a previous stage of this script, subtracted from the baseline)` : '') +
      ', sha256 manifest taken'
  );

  // ── PHASE 2 ────────────────────────────────────────────────────────────────
  head(2, 'refuse to stage over anything the apex already serves');
  // Manifest keys are relative to apexDist, so the apex-root-relative path a
  // docs file will occupy is `docs/<rel>`. Written that way explicitly rather
  // than by guessing a prefix, because a guess that resolved against the wrong
  // base would report "0 collisions" against an empty comparison.
  const at = (rel) => `${DOCS_DIR_NAME}/${rel.split(path.sep).join('/')}`;
  const collisions = docsFiles.filter((rel) => at(rel) in apexBefore);
  if (docsFiles.length === 0) refuse(2, 'the docs build listed 0 files, so the collision check would pass vacuously');
  if (collisions.length) {
    // Any collision here is a genuine problem, and the one thing that can cause
    // it is this script's own previous output that the marker does not account
    // for — which the block below diagnoses and, when it is safe, treats as
    // replaceable. What reaches THIS point has survived that, so it is a real
    // clash with a marketing-site file and the only honest answer is to stop.
    const ours = collisions.filter((rel) => priorStaged.has(at(rel)));
    const theirs = collisions.filter((rel) => !priorStaged.has(at(rel)));
    refuse(
      1,
      `the docs build would overwrite ${theirs.length} existing apex file(s) that no stage of this script recorded:\n` +
        `           ${theirs.slice(0, 20).join('\n           ')}\n` +
        (ours.length ? `         (a further ${ours.length} collided path(s) were recorded by an earlier stage and are being reported as this instead, which is itself a bug in this file.)\n` : '') +
        `       Refusing: those are the marketing site's files, not a stale copy of the docs.`
    );
  }
  ok(`${docsFiles.length} staged path(s) checked against ${apexCount} apex path(s): 0 collisions`);

  if (args.checkOnly) {
    if (!isDir(target)) refuse(1, `--check-only but ${target} does not exist`);
    ok('--check-only: verifying the existing staged tree without writing');
  } else {
    if (isDir(target)) {
      // Safe to delete, and the proof is above rather than here: Phase 1 has
      // already established that every file in this tree is recorded in the
      // marker's cumulative list, is in the current docs build, or is a name
      // this script creates — and has refused otherwise, naming the file. So
      // there is no second judgement to make here and no way for the two to
      // disagree. Kept as an explicit delete because the alternative is a stale
      // tree being carried into the next deploy, which is how a removed page
      // keeps being served.
      fs.rmSync(target, { recursive: true, force: true });
      info(`removed the previous staged tree (${priorStaged.size} path(s) this script had staged; see Phase 1 for what was in it)`);
    }
    // ── PHASE 3 ──────────────────────────────────────────────────────────────
    head(3, 'copy, then compare the copy by sha256');
    for (const rel of docsFiles) {
      const to = path.join(target, rel);
      fs.mkdirSync(path.dirname(to), { recursive: true });
      fs.copyFileSync(path.join(docsDist, rel), to);
    }
    const docsManifest = manifest(docsDist);
    const stagedCopy = manifest(target);
    const missing = Object.keys(docsManifest).filter((k) => !(k in stagedCopy));
    const differing = Object.keys(docsManifest).filter((k) => stagedCopy[k] !== docsManifest[k]);
    const extra = Object.keys(stagedCopy).filter((k) => !(k in docsManifest));
    if (missing.length || differing.length || extra.length) {
      refuse(1, `the staged copy is not the source: ${missing.length} missing, ${differing.length} differing, ${extra.length} extra.\n       A copy that has not been compared is not a copy.`);
    }
    ok(`${Object.keys(stagedCopy).length} files copied and all ${Object.keys(docsManifest).length} compared equal by sha256 (0 missing / 0 differing / 0 extra)`);
  }

  // ── PHASE 4 ────────────────────────────────────────────────────────────────
  head(4, "make the staged HTML satisfy the apex's Content-Security-Policy");
  const apexHeaders = parseHeaders(fs.readFileSync(path.join(apexDist, '_headers'), 'utf8'));
  const cspRules = apexHeaders.filter((r) => r.headers.some(([n]) => n === 'content-security-policy'));
  const csp = cspRules.length ? cspRules[cspRules.length - 1].headers.find(([n]) => n === 'content-security-policy')[1] : '';
  if (!csp) {
    info('the apex ships no Content-Security-Policy; the CSP step has nothing to satisfy and is a no-op');
  } else {
    const scanTarget = () => {
      const rels = walk(target);
      return {
        html: rels.filter((f) => f.endsWith('.html')).map((f) => path.join(target, f)),
        css: rels.filter((f) => f.endsWith('.css')).map((f) => path.join(target, f)),
      };
    };
    let s = scanTarget();
    const before = analyseCsp(csp, s.html, s.css);
    if (before.checked === 0) refuse(1, 'the CSP analysis examined 0 files, so its findings would be vacuous — treat this as the bug, not as a pass');
    if (!before.applicable) info(`CSP analysis skipped: ${before.reason}`);
    for (const f of before.findings) warn(`as staged, ${f}`);
    const needsExternalising = before.findings.some((f) => f.startsWith('script-src') || f.startsWith('style-src-elem'));
    if (!args.externalise) {
      info('--no-externalise: leaving inline scripts in place');
    } else if (needsExternalising) {
      const res = externaliseInlineScripts(target, walk(target).filter((f) => f.endsWith('.html')));
      if (res.total === 0) {
        refuse(
          1,
          'found 0 inline <script> elements to externalise, so the step that just reported a CSP violation did nothing. Either VitePress changed shape or the detector is wrong; both are reasons to stop.'
        );
      }
      s = scanTarget();
      const after = analyseCsp(csp, s.html, s.css);
      const still = after.findings.filter((f) => f.startsWith('script-src') || f.startsWith('style-src-elem'));
      if (still.length) refuse(1, `after externalising, ${still.join('; ')}`);
      ok(
        `${res.total} inline <script> element(s) across ${res.files} page(s) moved to ${res.unique} same-origin file(s) under ${BASE}assets/; script-src 'self' now satisfied with no change to the apex CSP`
      );
    } else if (before.applicable) {
      ok(`examined ${before.checked} file(s): no script-src or style-src-elem violation, so nothing to externalise`);
    }
    s = scanTarget();
    const post = analyseCsp(csp, s.html, s.css);
    for (const f of post.findings) {
      warn(`remaining, and NOT fixable from this repository: ${f}`);
    }
  }

  // ── PHASE 5 ────────────────────────────────────────────────────────────────
  head(5, 'generate /docs/sitemap.xml from the build, and verify what it claims');
  const stagedHtmlRel = walk(target).filter((f) => f.endsWith('.html')).sort();
  const { body: smBody, urls: smUrls } = buildDocsSitemap(stagedHtmlRel);
  if (smUrls.length === 0) refuse(1, 'the generated docs sitemap would contain 0 URLs, which is a failure of this script and not a finding about the docs');
  if (!args.checkOnly) fs.writeFileSync(path.join(target, 'sitemap.xml'), smBody);
  const smPath = path.join(target, 'sitemap.xml');
  if (!isFile(smPath)) refuse(2, 'sitemap.xml is not in the staged tree');
  const parsed = parseSitemap(fs.readFileSync(smPath, 'utf8'));
  if (!parsed.wellFormed) refuse(1, 'the generated docs sitemap is not a well-formed sitemap document');
  const smMissing = smUrls.filter((u) => !resolveInMerged(apexDist, u));
  if (smMissing.length) refuse(1, `${smMissing.length} URL(s) in the docs sitemap resolve to nothing in the merged output: ${smMissing.slice(0, 5).join(', ')}`);
  if (smUrls.some((u) => u.endsWith('/404.html'))) refuse(1, 'the docs sitemap lists 404.html');
  ok(`docs sitemap: ${parsed.locs.length} <loc> entries, all resolving to a file in the merged output, 404.html excluded`);
  summary.sitemapUrls = parsed.locs.length;

  // Duplicate check: a URL already submitted through one of the apex's own
  // child sitemaps is a URL being submitted twice, which is the other way this
  // merge could quietly cost something.
  const apexIndex = parseSitemap(fs.readFileSync(path.join(apexDist, 'sitemap.xml'), 'utf8'));
  if (apexIndex.kind !== 'index') refuse(2, `${apexDist}/sitemap.xml is not a <sitemapindex>`);
    const apexLocs = new Set();
    // The docs' OWN child is excluded, and the reason is worth stating because the
    // symptom looks exactly like a real finding.
    //
    // This set is built by reading every child the index names. Once the marketing
    // site lists `${BASE}sitemap.xml` as a child -- which it now does, and should,
    // because the docs are served from this host -- that child IS this sitemap, so
    // the comparison below puts the docs' URLs into a set and then checks the docs'
    // URLs against it. Every one is reported as a duplicate of itself:
    //
    //     stage-docs: REFUSED (FAILED) -- 34 docs URL(s) are already in an apex
    //     child sitemap
    //
    // A check comparing a list to itself is not a finding. Measured 2026-09-28; the
    // fix was proved against a patched copy before being applied here.
    //
    // Concatenated rather than joined: BASE already ends in a slash, so a join-based
    // form is one refactor away from a doubled slash and a path matching nothing.
    const docsOwnChild = `${BASE}sitemap.xml`;
    let skippedDocsChild = false;
    for (const child of apexIndex.locs) {
      const childPath = child.replace(SITE_ORIGIN, '');
      if (childPath === docsOwnChild) { skippedDocsChild = true; continue; }
      const cp = path.join(apexDist, path.relative('/', childPath));
      if (isFile(cp)) {
        const p = parseSitemap(fs.readFileSync(cp, 'utf8'));
        for (const l of p.locs) apexLocs.add(l);
      } else {
        warn(`apex sitemap index names ${childPath}, which is not in the build output; not compared`);
      }
    }
    const dupes = parsed.locs.filter((l) => apexLocs.has(l));
    if (dupes.length) refuse(1, `${dupes.length} docs URL(s) are already in an apex child sitemap: ${dupes.slice(0, 5).join(', ')}`);
    // The number of children COMPARED, not the number named. Claiming coverage of a
    // child that was deliberately skipped would be a reassuring constant -- the exact
    // defect class this script was hardened against elsewhere.
    const comparedChildren = apexIndex.locs.length - (skippedDocsChild ? 1 : 0);
    ok(`${apexLocs.size} URL(s) across ${comparedChildren} apex child sitemap(s) compared: 0 overlap with the docs sitemap` + (skippedDocsChild ? ` (excluding the docs' own child, ${docsOwnChild})` : ''));

  const docsReferenced = apexIndex.locs.some((l) => l.startsWith(`${SITE_ORIGIN}${BASE}`));
  if (!docsReferenced) {
    warn(
      `the apex sitemap index does not reference ${BASE}sitemap.xml, and robots.txt advertises only /sitemap.xml.\n` +
        `       So the docs sitemap exists and is correct but nothing points a crawler at it.\n` +
        `       That is a one-line change in the MARKETING repository, not this one:\n` +
        `         src/lib/sitemap.ts  ->  CHILD_SITEMAPS: add '${BASE}sitemap.xml'\n` +
        `       or\n` +
        `         src/pages/robots.txt.ts  ->  add  Sitemap: ${SITE_ORIGIN}${BASE}sitemap.xml\n` +
        `       Left as a warning, not a failure: it is the owner's call, and failing here would block a deploy on a change that is not this repository's to make.`
    );
  } else {
    ok('the apex sitemap index already references the docs sitemap');
  }

  // ── PHASE 6 ────────────────────────────────────────────────────────────────
  head(6, 'resolve every local URL in the staged output against the MERGED tree');
  const stagedFiles = walk(target);
  const htmlAbs = stagedFiles.filter((f) => f.endsWith('.html')).map((f) => path.join(target, f));
  const cssAbs = stagedFiles.filter((f) => f.endsWith('.css')).map((f) => path.join(target, f));
  if (htmlAbs.length === 0) refuse(1, '0 HTML files in the staged tree, so the resolution check would pass vacuously');
  if (cssAbs.length === 0) refuse(1, '0 CSS files in the staged tree, so the stylesheet reference check would pass vacuously — the font url()s live there and nowhere else');

  const perFile = new Map();
  let totalRefs = 0;
  const unresolved = [];
  const escapers = [];
  const outsideDocs = [];
  const buckets = { root: 0, relative: 0, external: 0, fragment: 0, data: 0 };
  for (const abs of [...htmlAbs, ...cssAbs]) {
    const rel = path.relative(target, abs);
    const text = fs.readFileSync(abs, 'utf8');
    const refs = abs.endsWith('.css') ? extractCssRefs(text) : extractHtmlRefs(text);
    if (abs.endsWith('.html') && refs.length === 0) {
      bad(`${rel}: 0 references extracted. A page with no references is either a broken extractor or a broken page; both are failures, and neither is a pass.`);
    }
    const pageUrl = pageUrlFor(rel);
    let n = 0;
    for (const { url, via } of refs) {
      totalRefs += 1;
      n += 1;
      if (url.startsWith('#') || /^(mailto|tel|javascript):/i.test(url)) {
        buckets.fragment += 1;
        continue;
      }
      if (url.startsWith('data:')) {
        buckets.data += 1;
        continue;
      }
      if (/^https?:\/\//i.test(url) || url.startsWith('//')) {
        buckets.external += 1;
        continue;
      }
      let urlPath;
      if (url.startsWith('/')) {
        buckets.root += 1;
        urlPath = url;
        if (!urlPath.startsWith(BASE)) escapers.push(`${rel} (via ${via}): ${urlPath}`);
      } else {
        buckets.relative += 1;
        urlPath = absolutise(pageUrl, url);
      }
      if (!resolveInMerged(apexDist, urlPath)) unresolved.push(`${rel} (via ${via}): ${url} -> ${urlPath}`);
      // A docs page that resolves only because of something the APEX happens to
      // serve would 404 on docs.jkbmsr.com, which deploys these same files at
      // their root. So self-containment is checked separately, against the docs
      // tree alone: the subdomain must keep working.
      //
      // The base prefix is stripped, because `siteRoot` here is the docs tree
      // while `urlPath` is a public URL. Passing both unstripped would look for
      // `docs/docs/assets/…` and report every single reference as unresolvable —
      // which is the failure mode this whole script exists to avoid, in the
      // shape of a check that is right about the site and wrong about itself.
      if (!resolveInMerged(target, urlPath.slice(BASE.length - 1))) {
        outsideDocs.push(`${rel} (via ${via}): ${urlPath}`);
      }
    }
    perFile.set(rel, n);
  }
  if (totalRefs === 0) refuse(1, 'extracted 0 references in total. That is a failure of the extractor, not a clean result.');
  summary.refsChecked = totalRefs;
  const thinnest = [...perFile.entries()].sort((a, b) => a[1] - b[1]).slice(0, 3);
  ok(
    `${totalRefs} reference(s) extracted from ${htmlAbs.length} HTML page(s) and ${cssAbs.length} stylesheet(s) — ${perFile.size} files, thinnest: ${thinnest.map(([f, n]) => `${f} (${n})`).join(', ')}`
  );
  info(`breakdown: ${buckets.root} root-absolute, ${buckets.relative} relative, ${buckets.external} external, ${buckets.data} data:, ${buckets.fragment} fragment/mailto/tel`);
  if (escapers.length) {
    for (const e of escapers.slice(0, 15)) bad(`escapes ${BASE}: ${e}`);
    refuse(1, `${escapers.length} reference(s) resolve against the apex root instead of ${BASE}. With base wrong, every stylesheet, the theme and every internal link resolves to the marketing site instead, and nothing throws.`);
  }
  ok(`0 references escape ${BASE} — the prefix check`);
  if (unresolved.length) {
    for (const u of unresolved.slice(0, 15)) bad(`no such file in the merged output: ${u}`);
    refuse(1, `${unresolved.length} reference(s) resolve to nothing in the merged output. A file existing in the docs build is not evidence that the edge will serve it under ${BASE}.`);
  }
  ok(`0 references resolve to nothing in the merged output — the existence check, which is strictly stronger than the prefix check above`);
  if (outsideDocs.length) {
    for (const u of outsideDocs.slice(0, 15)) bad(`resolves only because of the apex, not from the docs build: ${u}`);
    refuse(1, `${outsideDocs.length} reference(s) resolve outside the docs tree. They would work on the apex and 404 on docs.jkbmsr.com, which deploys these same files at their own root.`);
  }
  ok(`0 references depend on an apex file: the docs tree is self-contained, so docs.jkbmsr.com keeps serving the same build unchanged`);

  // ── PHASE 7 ────────────────────────────────────────────────────────────────
  head(7, "account for every apex header and redirect rule, and say which reach /docs/");
  const apexRedirects = parseRedirects(fs.readFileSync(path.join(apexDist, '_redirects'), 'utf8'));
  if (apexRedirects.length === 0) refuse(2, 'the apex _redirects parsed to 0 rules, so "no rule shadows /docs/" would be vacuous');
  if (apexHeaders.length === 0) refuse(2, 'the apex _headers parsed to 0 rules, so "no header rule overlaps" would be vacuous');
  ok(`parsed ${apexHeaders.length} header rule(s) and ${apexRedirects.length} redirect rule(s) — both counts asserted non-zero`);

  const shadowing = apexRedirects.filter((r) => pagesGlobToRegExp(r.source).test(BASE) || pagesGlobToRegExp(r.source).test(`${BASE}index.html`));
  if (shadowing.length) {
    for (const s of shadowing) bad(`redirect ${s.source} -> ${s.target} ${s.status} matches ${BASE}; a redirect takes precedence over a static asset at the same path`);
    refuse(1, `${shadowing.length} redirect rule(s) would shadow ${BASE}. The staged tree would look correct and the pages would be unreachable.`);
  }
  ok(`0 of ${apexRedirects.length} redirect rule(s) match ${BASE} or ${BASE}index.html`);

  // THE APPEND QUESTION, decided on the rule set rather than on sampled paths.
  //
  // Pages appends every matching rule's value for a header rather than picking
  // the most specific match, which is how this project once served
  //   content-type: application/atom+xml; charset=utf-8, application/rss+xml; charset=utf-8
  // — two comma-separated media types in one field, which RFC 7231 does not
  // permit, and invisible in the build directory. The fix was to make each URL
  // match exactly ONE Content-Type rule "whether Pages appends or overrides", so
  // the file no longer depends on which.
  //
  // The same reasoning applies here and is asserted exhaustively: if no two rules
  // that can match the same path set the same header, there is nothing for Pages
  // to append, and the answer does not depend on the edge's actual behaviour.
  // That is a stronger and cleaner argument than observing one URL.
  //
  // ONE THING THIS CANNOT DO, and it is the reason the control below exists: the
  // local preview does not reproduce the append behaviour. Measured 2026-09-28
  // on this host — a `/docs/*` rule setting `X-Frame-Options` and `Cache-Control`
  // alongside the existing `/*` rule produced 14 headers with no duplication, and
  // `astro preview` reported "Parsed 10 valid header rules" while serving
  // single-valued headers. So the emulator picks the most specific match and the
  // production edge does not. **Do not verify this on the preview.** Verify it on
  // the rule set, as above, and on the live site over a raw TLS socket.
  const overlapping = overlappingHeaderRules(apexHeaders);
  const rulePairs = (apexHeaders.length * (apexHeaders.length - 1)) / 2;
  for (const o of overlapping) {
    bad(`${o.header}: ${o.a} and ${o.b} both set it, and they overlap (witness path ${o.witness}) — Pages would append, producing one field with two values`);
  }
  if (overlapping.length) {
    refuse(
      1,
      `${overlapping.length} header(s) are set by two overlapping rules in the apex _headers. Whether or not you can observe the append locally, the file no longer depends on the edge picking the most specific match.`
    );
  }
  ok(
    `all ${rulePairs} rule pair(s) in the apex _headers examined: no header is set by two rules that can match the same path, so there is nothing for Pages to append`
  );

  // What /docs/ will actually receive, still computed per-path so the answer is
  // a list rather than an inference.
  const samplePaths = [`${BASE}`, `${BASE}index.html`, `${BASE}404.html`, `${BASE}sitemap.xml`, `${BASE}api/index.html`, `${BASE}assets/style.css`, `${BASE}favicon.svg`, `${BASE}getting-started/first-device-setup.html`];
  const reach = new Set();
  let perPathDoubles = 0;
  for (const p of samplePaths) {
    for (const [name, entries] of headersFor(apexHeaders, p)) {
      if (entries.length > 1) perPathDoubles += 1;
      else reach.add(name);
    }
  }
  if (perPathDoubles) refuse(1, `${perPathDoubles} of the ${samplePaths.length} representative /docs/ paths receive a doubly-set header`);
  ok(`each of the ${samplePaths.length} representative /docs/ paths receives ${reach.size} header(s), every one of them from a single rule`);
  info(`those headers: ${[...reach].sort().join(', ')}`);
  info('NOT among them: the feed Content-Types, whose rules are the exact paths /feed/ and /feed/atom/ — so the two-media-type append cannot reach the docs');
  ok('the staged tree adds no _headers and no _redirects, so the apex files are the only ones the deployment reads, and /docs/ is governed by rules that already govern the rest of the site');


  // ── PHASE 8 ────────────────────────────────────────────────────────────────
  head(8, 'prove the apex files are unharmed, and report what the apex still points at');
  const apexAfter = manifest(apexDist);
  const removed = Object.keys(apexBefore).filter((k) => !(k in apexAfter));
  const changed = Object.keys(apexBefore).filter((k) => k in apexAfter && apexAfter[k] !== apexBefore[k]);
  const added = Object.keys(apexAfter).filter((k) => !(k in apexBefore));
  summary.apexFilesChecked = apexCount;
  if (removed.length || changed.length) {
    for (const r of removed.slice(0, 10)) bad(`REMOVED ${r}`);
    for (const c of changed.slice(0, 10)) bad(`CHANGED ${c}`);
    refuse(1, `the merge modified the marketing site: ${changed.length} changed, ${removed.length} removed. A merge that breaks the marketing site to fix the docs is a bad trade.`);
  }
  const addedOutsideDocs = added.filter((k) => !k.startsWith(`${DOCS_DIR_NAME}/`));
  if (addedOutsideDocs.length) {
    for (const a of addedOutsideDocs.slice(0, 10)) bad(`ADDED OUTSIDE ${DOCS_DIR_NAME}/: ${a}`);
    refuse(1, `${addedOutsideDocs.length} file(s) appeared outside ${DOCS_DIR_NAME}/. The stage may only add files under it.`);
  }
  ok(
    `${apexCount} pre-existing apex file(s) all still present and byte-identical by sha256; ${added.length} added, every one of them under ${DOCS_DIR_NAME}/`
  );

  const SPOT = [
    'index.html',
    'blog/index.html',
    'feed/index.html',
    'feed/atom/index.html',
    'sitemap.xml',
    'robots.txt',
    'privacy/index.html',
    '2026/06/index.html',
    '2026/index.html',
    'author/jkbmsr/index.html',
    '404.html',
    '_headers',
    '_redirects',
  ];
  const missingSpot = SPOT.filter((p) => !(p in apexAfter));
  if (missingSpot.length) refuse(1, `spot-checked apex paths missing after the merge: ${missingSpot.join(', ')}`);
  ok(`${SPOT.length} spot-checked apex paths present and unchanged (${SPOT.slice(0, 9).join(', ')} …)`);

  // An inbound-link count, so "the apex links to the docs subdomain, not to
  // /docs/" is a number this run prints rather than a sentence in a document
  // that decays. It is reported, not enforced: repointing 147 links is the
  // owner's call, in the other repository.
  const apexHtml = walk(apexDist).filter((f) => f.endsWith('.html') && !f.startsWith('docs/'));
  let toDocsPath = 0;
  let toDocsHost = 0;
  for (const rel of apexHtml) {
    const h = fs.readFileSync(path.join(apexDist, rel), 'utf8');
    for (const m of h.matchAll(/href="([^"]+)"/g)) {
      if (m[1].startsWith(BASE) || m[1].startsWith('.')) toDocsPath += 1;
      else if (m[1].startsWith('https://docs.jkbmsr.com')) toDocsHost += 1;
    }
  }
  info(`apex pages scanned: ${apexHtml.length}`);
  info(`links from the apex to ${BASE}: ${toDocsPath}`);
  info(`links from the apex to https://docs.jkbmsr.com: ${toDocsHost}`);
  if (toDocsPath === 0) {
    warn(
      `nothing on the apex links to ${BASE}, and ${toDocsHost} link(s) point at https://docs.jkbmsr.com instead.\n` +
        `       So once published, ${BASE} would be an orphan AND a byte-for-byte duplicate of the subdomain, with no canonical on either.\n` +
        `       Two decisions, both in the MARKETING repository, both the owner's:\n` +
        `         (a) repoint those ${toDocsHost} link(s) at ${BASE} so the copy on the apex is reachable from its own site;\n` +
        `         (b) declare a canonical for the docs. Adding <link rel="canonical"> via a VitePress\n` +
        `             transformHead is a few lines in docs/docs/.vitepress/config.ts and would apply to BOTH\n` +
        `             deployments, telling search engines the apex is canonical and the subdomain is not.`
    );
  }
  summary.inboundDocsPathLinks = toDocsPath;
  summary.inboundDocsHostLinks = toDocsHost;

  // ── PHASE 9 ───────────────────────────────────────────────────────────────
  // The marker is written LAST, after every file this run will create exists.
  // Written earlier it would describe an incomplete tree, and then the next
  // run's own safety check would reject its own predecessor's output for
  // containing a file the marker never mentioned — which is precisely what
  // happened the first time this was written in the middle of the run.
  head(9, 'record what this script is responsible for');
  if (args.checkOnly) {
    ok('--check-only: the marker was not rewritten');
  } else {
    const recorded = walk(target).sort();
    fs.writeFileSync(
      markerFile(apexDist),
      `${JSON.stringify(
        {
          note: 'Written by scripts/stage-docs.mjs, after the stage completed. Its presence, plus every file in dist/client/docs appearing in stagedFiles, is the only basis on which that tree will be replaced.',
          base: BASE,
          siteOrigin: SITE_ORIGIN,
          docsDist,
          apexDist,
          sourceFileCount: docsFiles.length,
          sourceManifestSha256: sha256(JSON.stringify(manifest(docsDist))),
          // What THIS run produced.
          stagedFiles: recorded,
          // Every path this script has ever put in this tree, so a later run can
          // still tell its own leftovers from a file somebody else added.
          everStaged: [...new Set([...priorStaged, ...recorded.map((f) => at(f))])].sort(),
        },
        null,
        2
      )}\n`
    );
    ok(`${recorded.length} path(s) recorded in ${markerFile(apexDist)}`);
    info('the marker is in dist/, the parent of the Pages upload root, so it is never published and astro build does not clear it');
  }

  // ── summary ────────────────────────────────────────────────────────────────
  const stagedCount = walk(target).length;
  summary.staged = stagedCount;
  head(10, 'summary');
  process.stdout.write(`   staged files        ${stagedCount} under ${apexDist}/docs\n`);
  process.stdout.write(`   apex files intact   ${apexCount} (0 changed, 0 removed)\n`);
  process.stdout.write(`   references resolved ${totalRefs} (${htmlAbs.length} pages, ${cssAbs.length} stylesheets)\n`);
  process.stdout.write(`   docs sitemap URLs   ${parsed.locs.length}\n`);
  process.stdout.write(`   warnings            ${warnings}\n`);
  process.stdout.write(`\n   Nothing was deployed. To publish, from ${path.dirname(apexDist)}:\n`);
  process.stdout.write(
    '     astro preview                       # browse http://localhost:4321/docs/  (IPv6 [::1] only)\n' +
      '     # then stop preview, and only then:\n' +
      "     rm -f  dist/client/wrangler.json && rm -rf dist/client/.wrangler\n" +
      '     # Pages rejects that shape; astro preview needs wrangler.json to know a build exists.\n' +
      '     npx wrangler@4.118.0 pages deploy dist/client --project-name jkbmsr-marketing --branch main\n'
  );
  if (warnings) {
    process.stdout.write(`\n   ${YEL(`${warnings} warning(s) above are decisions for the owner, not defects in this script.`)}\n`);
  }
  summary.warnings = warnings;
  process.stdout.write(`\n${GRN('VERDICT: STAGED AND VERIFIED')}\n`);
  if (process.env.STAGE_DOCS_JSON) process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
  return 0;
}

try {
  // Only when invoked, not when imported. Without this guard, the test's
  // `import` would run the whole staging pipeline against the real apex.
  if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    process.exit(main());
  }
} catch (e) {
  if (e instanceof Refuse) {
    process.stdout.write(`\n${RED(`stage-docs: REFUSED (${e.code === 2 ? 'COULD NOT RUN' : 'FAILED'})`)} — ${e.message}\n`);
    process.exit(e.code);
  }
  process.stdout.write(`\n${RED('stage-docs: ERROR')} — ${e && e.stack ? e.stack : e}\n`);
  process.exit(2);
}
