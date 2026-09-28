#!/usr/bin/env node
/**
 * stage-docs.test.mjs — prove every guard in stage-docs.mjs can actually fail.
 *
 * WHY THIS FILE EXISTS, and why it is not optional
 *   stage-docs.mjs prints "ok" a great deal, and most of what it prints is a
 *   negative result: 0 escapes, 0 collisions, 0 changed, 0 unresolvable. A
 *   negative result from a check that cannot fail is worse than no check,
 *   because it is read as assurance. This project has paid for that specific
 *   mistake three times in one session — a regex reporting `cards=0` for pages
 *   that had three, twice because the pattern was wrong and once because a loop
 *   variable was reused — and the tell in all three was the same: a KNOWN-GOOD
 *   control returning the same value as the thing under test.
 *
 *   So every negative in that script is here paired with a fixture that must
 *   make it go red, and a control that must stay green. Where a guard cannot be
 *   reached without running the whole pipeline, it is reproduced in miniature
 *   and the miniature is asserted, rather than the guard being left untested and
 *   described as though it were.
 *
 * Run: node scripts/stage-docs.test.mjs
 * Exit: 0 every fixture behaved as specified, 1 one did not.
 */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

import {
  extractHtmlRefs,
  extractCssRefs,
  runExtractorSelfTest,
  parseHeaders,
  parseRedirects,
  headersFor,
  pagesGlobToRegExp,
  probePathsFor,
  overlappingHeaderRules,
  buildDocsSitemap,
  parseSitemap,
  pageUrlFor,
  resolveInMerged,
  analyseCsp,
  BASE,
} from './stage-docs.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));

let passed = 0;
let failed = 0;
const failures = [];

function t(name, fn) {
  try {
    fn();
    passed += 1;
    process.stdout.write(`   ok    ${name}\n`);
  } catch (e) {
    failed += 1;
    failures.push(`${name}: ${e.message}`);
    process.stdout.write(`   FAIL  ${name}\n         ${String(e.message).split('\n').join('\n         ')}\n`);
  }
}
function group(name) {
  process.stdout.write(`\n== ${name}\n`);
}
const scratch = () => fs.mkdtempSync(path.join(os.tmpdir(), 'stage-docs-test-'));

// ─────────────────────────────────────────────────── the extractor's own guard ──

group('the extractor self-test can fail (positive control for the guard)');

t('the real extractor passes its own self-test', () => {
  const n = runExtractorSelfTest();
  assert.equal(typeof n, 'number');
  assert.ok(n >= 5, `expected at least 5 assertions, got ${n}`);
});

t('a self-test that only ever passes is rejected: an extractor that finds NOTHING is broken', () => {
  // This is the exact shape of the bug this file exists for. An extractor
  // returning [] makes every downstream count read 0, every assertion on that
  // count vacuously true, and the run prints all green.
  assert.throws(() => runExtractorSelfTest(() => [], () => []), /failed its own self-test/);
});

t('…and one that misses only the stylesheet url() is rejected too', () => {
  assert.throws(() => runExtractorSelfTest(extractHtmlRefs, () => []), /failed its own self-test/);
});

t('…and one that misses only og:image is rejected too', () => {
  const htmlOnly = (h) => extractHtmlRefs(h).filter((r) => !r.via.startsWith('meta:'));
  assert.throws(() => runExtractorSelfTest(htmlOnly, extractCssRefs), /failed its own self-test/);
});

// ─────────────────────────────────────────────────── the base-prefix assertion ──

group('the base-prefix check rejects a build whose base is wrong');

// The control runs first and must be green. If the subject and the control
// return the same thing, the instrument is broken and every negative after this
// is meaningless — which is the lesson from the `cards=0` incident, encoded.
const CORRECT_PAGE = '<link href="/docs/assets/style.css"><img src="/docs/favicon.svg"><a href="/docs/api/">a</a>';
const WRONG_BASE_PAGE = '<link href="/assets/style.css"><img src="/favicon.svg"><a href="/api/">a</a>';

t('CONTROL: the correct page yields 3 references, all under /docs/', () => {
  const refs = extractHtmlRefs(CORRECT_PAGE);
  assert.equal(refs.length, 3, `control returned ${refs.length}, expected 3`);
  for (const r of refs) assert.ok(r.url.startsWith(BASE), `${r.url} does not start with ${BASE}`);
});

t('the same instrument reports the wrong-base page as escaping /docs/', () => {
  const refs = extractHtmlRefs(WRONG_BASE_PAGE);
  assert.equal(refs.length, 3, 'the wrong-base page must yield the SAME count as the control');
  const escapers = refs.filter((r) => !r.url.startsWith(BASE));
  assert.equal(escapers.length, 3, `expected all 3 to escape, got ${escapers.length}`);
});

t('the double-prefix bug this repo actually hit (/docs/docs/…) is caught by EXISTENCE, not by the prefix', () => {
  // `/docs/docs/favicon.svg` IS under `/docs/`, so a prefix-only check passes it.
  // That is why the existence check exists, and this asserts the difference
  // rather than asserting the comment. It is also a real regression replayed:
  // writing `${BASE}` into `themeConfig.logo` produced exactly this URL, and the
  // prefix check passed it while the existence check caught it on the first run.
  const url = '/docs/docs/favicon.svg';
  assert.ok(url.startsWith(BASE), 'precondition: this URL does start with the base');
  const merged = scratch();
  try {
    fs.mkdirSync(path.join(merged, 'docs', 'logos'), { recursive: true });
    fs.writeFileSync(path.join(merged, 'docs', 'favicon.svg'), 'svg');
    assert.equal(resolveInMerged(merged, '/docs/favicon.svg'), 'docs/favicon.svg');
    assert.equal(resolveInMerged(merged, url), null, 'the doubled path must NOT resolve');
  } finally {
    fs.rmSync(merged, { recursive: true, force: true });
  }
});

group('cleanUrls: a link with no extension still resolves to the .html on disk');

t('CONTROL: /docs/api/index resolves to docs/api/index.html', () => {
  const root = scratch();
  try {
    fs.mkdirSync(path.join(root, 'docs', 'api'), { recursive: true });
    fs.writeFileSync(path.join(root, 'docs', 'api', 'index.html'), 'x');
    assert.equal(resolveInMerged(root, '/docs/api/index'), 'docs/api/index.html');
    assert.equal(resolveInMerged(root, '/docs/api/'), 'docs/api/index.html');
    assert.equal(resolveInMerged(root, '/docs/api/index.html'), 'docs/api/index.html');
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

t('a genuinely absent path resolves to null, so the check is not always true', () => {
  const root = scratch();
  try {
    fs.mkdirSync(path.join(root, 'docs'), { recursive: true });
    assert.equal(resolveInMerged(root, '/docs/nope.html'), null);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

// ───────────────────────────────────────────────── the sitemap, derived not listed ──

group('the docs sitemap is derived from the files, and 404.html is excluded');

t('CONTROL: index.html maps to the directory URL and nested pages map correctly', () => {
  assert.equal(pageUrlFor('index.html'), '/docs/');
  assert.equal(pageUrlFor('api/index.html'), '/docs/api/');
  assert.equal(pageUrlFor('pricing.html'), '/docs/pricing');
  assert.equal(pageUrlFor('getting-started/first-device-setup.html'), '/docs/getting-started/first-device-setup');
});

t('a page that EXISTS cannot be left out by forgetting: the list is the file list', () => {
  const files = ['index.html', 'pricing.html', 'safety/ota-safety.html', 'api/index.html', '404.html'];
  const { urls } = buildDocsSitemap(files);
  assert.equal(urls.length, 4, '404.html must be excluded, the other four included');
  assert.ok(urls.includes('/docs/safety/ota-safety'));
  assert.ok(!urls.some((u) => u.includes('404')));
});

t('a sitemap listing 404.html is a defect, and the generated one never does', () => {
  const { body } = buildDocsSitemap(['index.html', '404.html']);
  assert.ok(!body.includes('404'));
  const parsed = parseSitemap(body);
  assert.equal(parsed.kind, 'urlset');
  assert.ok(parsed.wellFormed, 'the generated document must parse as well-formed');
});

t('a truncated or unclosed sitemap does not pass parseSitemap', () => {
  // The audit's check 6/7 are named "valid" and "parses" while only counting.
  // This asserts the cheap version cannot be fooled by an unclosed document.
  assert.equal(parseSitemap('<?xml version="1.0"?><urlset><url><loc>x</loc></url>').wellFormed, false);
  assert.equal(parseSitemap('not xml at all').kind, 'unknown');
});

// ─────────────────────────────────────────────── Pages glob semantics, and the append ──

group('the Pages wildcard really does cross "/" (measured, not assumed)');

t('a three-segment path matches a one-segment rule', () => {
  // The live apex serves `Cache-Control: public, max-age=604800` on
  // /assets/img/ble-shots/01-status-live.jpg and the only rule that could
  // supply it is `/assets/*`. That is the positive control for the assumption.
  const re = pagesGlobToRegExp('/assets/*');
  assert.ok(re.test('/assets/img/ble-shots/01-status-live.jpg'), 'the live observation requires * to cross /');
  assert.ok(re.test('/assets/site.css'));
  assert.ok(!re.test('/docs/assets/site.css'), 'and the rule must still be anchored at the root');
});

t('a `:name` placeholder matches exactly one segment', () => {
  const re = pagesGlobToRegExp('/x/:id');
  assert.ok(re.test('/x/1'));
  assert.ok(!re.test('/x/1/2'));
});

group('the _headers append hazard: the question is "set by more than one rule"');

const APPEND_FIXTURE = `# a comment, ignored
/*
  X-Frame-Options: DENY
  Content-Security-Policy: default-src 'none'; script-src 'self'

/docs/*
  Cache-Control: public, max-age=604800

/feed/
  Content-Type: application/rss+xml; charset=utf-8
`;

t('CONTROL: a header set by one rule is not reported as appended', () => {
  const rules = parseHeaders(APPEND_FIXTURE);
  const applied = headersFor(rules, '/docs/index.html');
  assert.equal(applied.get('x-frame-options').length, 1);
  assert.equal(applied.get('cache-control').length, 1);
});

t('two overlapping rules setting the SAME header are reported, which is the append bug', () => {
  // This is the shape that produced
  //   content-type: application/atom+xml; charset=utf-8, application/rss+xml; charset=utf-8
  const rules = parseHeaders(APPEND_FIXTURE + '\n/*\n  Cache-Control: public, max-age=0, must-revalidate\n');
  const applied = headersFor(rules, '/docs/index.html');
  const cc = applied.get('cache-control');
  assert.equal(cc.length, 2, 'expected both rules to reach /docs/index.html');
  assert.deepEqual(
    cc.map((e) => e.source).sort(),
    ['/*', '/docs/*'],
    'and the reported sources must name the rules, so the message is diagnosable'
  );
});

t('a header only one rule matches is still applied to the right paths', () => {
  const rules = parseHeaders(APPEND_FIXTURE);
  assert.equal(headersFor(rules, '/feed/').get('content-type')[0].value, 'application/rss+xml; charset=utf-8');
  assert.equal(headersFor(rules, '/docs/').get('content-type'), undefined, '/docs/ must not pick up the feed rule');
});

t('a comment-only line is not a rule', () => {
  assert.equal(parseHeaders('# nothing\n\n').length, 0);
});

group('the append check is EXHAUSTIVE over rule pairs, not sampled over paths');

const REAL_APEX_HEADERS = fs.readFileSync(
  path.resolve(HERE, '..', '..', 'jkbmsr-site', 'dist', 'client', '_headers'),
  'utf8'
);

t('CONTROL: the real apex _headers is the most specific match, not the most recent', () => {
  // The regression that is easy to reintroduce: a narrow rule placed AFTER a
  // broad one, with a comment claiming order decides. If a future edit adds
  // `/docs/*` with `X-Frame-Options` next to the `/*` rule that already sets
  // it, the two values land in one field at the edge. That pair is what the
  // exhaustive check below exists to refuse, and this asserts it is detectable
  // on the file as it stands plus that one line.
  const rules = parseHeaders(REAL_APEX_HEADERS);
  assert.ok(rules.length >= 8, `expected the real file to parse to >= 8 rules, got ${rules.length}`);
  assert.deepEqual(overlappingHeaderRules(rules), [], 'the shipped _headers must have no overlapping same-header pair');
  assert.ok(rules.some((r) => r.source === '/*'), 'and the /* rule must be present for this control to mean anything');
  assert.ok(rules.some((r) => r.source === '/assets/*'), 'and /assets/* too — the pair the live measurement proves crosses /');
});

t('adding one /docs/* rule that re-sets a /* header IS detected, with a witness path', () => {
  const rules = parseHeaders(`${REAL_APEX_HEADERS}\n/docs/*\n  X-Frame-Options: SAMEORIGIN\n`);
  const found = overlappingHeaderRules(rules);
  assert.equal(found.length, 1, `expected exactly one overlap, got ${JSON.stringify(found)}`);
  assert.equal(found[0].header, 'x-frame-options');
  assert.ok(found[0].witness.startsWith('/docs/'), `the witness must be a /docs/ path, got ${found[0].witness}`);
});

t('the overlap check finds a pair that no sampled path list would have covered', () => {
  // This is the reason the check is exhaustive: the overlap exists on
  // /deep/nested/path/only, which is not in any list anyone would write down,
  // and a path-sampling check reports zero for it.
  const rules = parseHeaders('/deep/*\n  X-Test: 1\n\n/*\n  X-Test: 2\n');
  const found = overlappingHeaderRules(rules);
  assert.equal(found.length, 1);
  assert.equal(found[0].a, '/deep/*');
  assert.equal(found[0].b, '/*');
});

t('disjoint sources setting the same header are NOT reported', () => {
  const rules = parseHeaders('/feed/\n  Content-Type: application/rss+xml; charset=utf-8\n\n/feed/atom/\n  Content-Type: application/atom+xml; charset=utf-8\n');
  assert.deepEqual(overlappingHeaderRules(rules), [], 'exact sibling paths are the shape the existing fix relies on');
});

t('different headers on overlapping sources are NOT reported', () => {
  const rules = parseHeaders('/*\n  X-A: 1\n\n/docs/*\n  X-B: 2\n');
  assert.deepEqual(overlappingHeaderRules(rules), [], 'overlap only matters when the HEADER is the same');
});

t('probePathsFor expands a wildcard to a NESTED path, which is the case that matters', () => {
  // Without a nested expansion, `/*` and `/docs/*` are judged disjoint and the
  // check reports zero on a file that would append at the edge.
  const probes = probePathsFor('/*');
  assert.ok(probes.includes('/'), 'the empty expansion');
  assert.ok(probes.includes('/x'), 'the single-segment expansion');
  assert.ok(probes.includes('/x/y'), 'the NESTED expansion — without this the whole check is blind');
  const docProbes = probePathsFor('/docs/*');
  assert.ok(docProbes.includes('/docs/x/y'));
});

// ─────────────────────────────────────────────────────────────────── redirects ──

group('a redirect shadows a static asset, so shadowing /docs/ must be fatal');

t('CONTROL: none of the real apex redirect sources match /docs/', () => {
  const apexHeaders = path.resolve(HERE, '..', '..', 'jkbmsr-site', 'dist', 'client', '_redirects');
  let text;
  try {
    text = fs.readFileSync(apexHeaders, 'utf8');
  } catch {
    process.stdout.write('   ..    (apex _redirects not present; using the in-file fixture instead)\n');
    text = '/index.php  /  301\n/feed/rdf/  /feed/  301\n/page/2/  /blog/page/2/  301\n';
  }
  const rules = parseRedirects(text);
  assert.ok(rules.length > 0, 'a zero-rule parse would make the negative vacuous');
  const shadowing = rules.filter((r) => pagesGlobToRegExp(r.source).test(BASE) || pagesGlobToRegExp(r.source).test(`${BASE}index.html`));
  assert.deepEqual(shadowing.map((s) => s.source), []);
});

t('a careless /docs* rule IS detected', () => {
  const rules = parseRedirects('/docs*  /  301\n');
  assert.equal(rules.length, 1);
  assert.ok(pagesGlobToRegExp(rules[0].source).test('/docs/'));
});

t('a trailing comment on a redirect line is not part of the target', () => {
  assert.deepEqual(parseRedirects('/a  /b  301  # why\n'), [{ source: '/a', target: '/b', status: 301 }]);
});

// ─────────────────────────────────────────────────────────────────── the CSP ───

group('the CSP analysis, on the real shape the apex ships');

const APEX_CSP =
  "default-src 'none'; base-uri 'none'; object-src 'none'; frame-ancestors 'none'; form-action 'self'; " +
  "script-src 'self'; script-src-attr 'none'; style-src 'self'; style-src-elem 'self'; " +
  "style-src-attr 'unsafe-inline'; img-src 'self'; font-src 'self'; connect-src 'self'";

function fakeFile(spec) {
  const root = scratch();
  for (const [rel, body] of Object.entries(spec)) {
    const abs = path.join(root, rel);
    fs.mkdirSync(path.dirname(abs), { recursive: true });
    fs.writeFileSync(abs, body);
  }
  return root;
}

t('CONTROL: a page with no inline script, no data: and no inline style reports nothing', () => {
  const root = fakeFile({
    'a/index.html': '<link rel="stylesheet" href="/docs/s.css"><script src="/docs/app.js"></script>',
    'a/s.css': 'body{color:#000}',
  });
  try {
    const r = analyseCsp(APEX_CSP, [path.join(root, 'a/index.html')], [path.join(root, 'a/s.css')]);
    assert.equal(r.checked, 2, 'the file count must be reported, or "0 findings" means nothing');
    assert.deepEqual(r.findings, [], `expected no findings, got ${JSON.stringify(r.findings)}`);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

t('the measured 140 inline scripts are reported, and the number is the real one', () => {
  // Built for exactly this: 4 inline scripts on each of 35 pages.
  const scripts = '<script>a()</script><script id="check-dark-mode">b()</script><script id="check-mac-os">c()</script><script>window.x=1</script>';
  const spec = {};
  for (let i = 0; i < 35; i += 1) spec[`p${i}/index.html`] = scripts;
  const root = fakeFile(spec);
  try {
    const r = analyseCsp(APEX_CSP, Object.keys(spec).map((k) => path.join(root, k)), []);
    assert.equal(r.inlineScripts, 140);
    assert.equal(r.findings.length, 1);
    assert.match(r.findings[0], /^script-src 'self'.*140 inline/);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

t('a data: image inside a STYLESHEET is reported — the HTML-only blind spot', () => {
  // An audit check in this project's history was named for scanning for Google
  // Fonts, read HTML only, and so passed a @import living in a stylesheet. The
  // same class of miss, in the same direction: the place nobody looked.
  const root = fakeFile({
    'a/index.html': '<link rel="stylesheet" href="/docs/s.css">',
    'a/s.css': '.vpi-social-github{--icon:url("data:image/svg+xml,%3Csvg%3E")}',
  });
  try {
    const r = analyseCsp(APEX_CSP, [path.join(root, 'a/index.html')], [path.join(root, 'a/s.css')]);
    assert.equal(r.dataUrls, 1);
    assert.ok(r.findings.some((f) => f.startsWith('img-src')), `expected an img-src finding, got ${JSON.stringify(r.findings)}`);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

t('the same documents are clean once the scripts are externalised', () => {
  const externalised = '<link rel="stylesheet" href="/docs/s.css"><script src="/docs/assets/inline-abc.js"></script>';
  const root = fakeFile({ 'a/index.html': externalised, 'a/s.css': 'body{}' });
  try {
    const r = analyseCsp(APEX_CSP, [path.join(root, 'a/index.html')], [path.join(root, 'a/s.css')]);
    assert.deepEqual(r.findings, []);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

t('an inline event handler is reported against script-src-attr none', () => {
  const root = fakeFile({ 'a/index.html': '<button onclick="go()">x</button>' });
  try {
    const r = analyseCsp(APEX_CSP, [path.join(root, 'a/index.html')], []);
    assert.ok(r.findings.some((f) => f.startsWith('script-src-attr')), JSON.stringify(r.findings));
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

t('a relaxed apex CSP makes the analysis report nothing rather than inventing a violation', () => {
  const relaxed = "default-src 'self'; script-src 'self' 'unsafe-inline'; img-src 'self' data:";
  const root = fakeFile({ 'a/index.html': '<script>a()</script><img src="data:image/svg+xml,x">' });
  try {
    const r = analyseCsp(relaxed, [path.join(root, 'a/index.html')], []);
    assert.deepEqual(r.findings, []);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

// ────────────────────────────────────────────────────────────────── summary ──

process.stdout.write(`\n${'='.repeat(72)}\n`);
process.stdout.write(`  ${passed} passed, ${failed} failed\n`);
if (failed) {
  process.stdout.write(`\n${failures.map((f) => `  - ${f}`).join('\n')}\n`);
  process.stdout.write('\nA guard that has never been seen to reject anything is not known to work.\n');
  process.exit(1);
}
process.stdout.write('\nVERDICT: every guard was shown to fail on input that should make it fail.\n');
