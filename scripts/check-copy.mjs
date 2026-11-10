#!/usr/bin/env node
// Fails when an em dash (U+2014) reaches product copy in this repository.
//
// The house style is plain punctuation: a full stop, a comma or a colon chosen for
// the sentence. Two surfaces are covered here, because they are the two this repo
// owns and a reader can see:
//
//   apps/*/lib/**/*.dart   user-facing strings in the three Android apps
//   docs/docs/**/*.md      the documentation served at jkbmsr.com/docs/
//
// Repository READMEs are developer material, like a comment: they are not
// published, so they are left alone. The same line is drawn here as in the
// source: what a reader can see is copy, everything else is not.
//
// Code comments are not copy. A comment is where the reasoning belongs, and it is
// never rendered, so comment lines are skipped rather than rewritten. That
// distinction is the one judgement this file makes, and it is made narrowly: a
// line whose first non-space characters are `//`, `///`, `*` or inside a `/* */`
// block is a comment. A `//` inside a string literal would fool it, which is why
// the report names the line and prints the text instead of silently rewriting.
//
// Usage: node scripts/check-copy.mjs [--quiet]

import { readdir, readFile } from "node:fs/promises";
import { join, relative, extname } from "node:path";

const ROOT = process.cwd();
const DASH = "\u2014";
const SKIP_DIRS = new Set(["node_modules", ".git", "build", ".dart_tool", ".vitepress", "dist"]);

async function* walk(dir) {
  let entries;
  try {
    entries = await readdir(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const e of entries) {
    if (SKIP_DIRS.has(e.name)) continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) yield* walk(p);
    else yield p;
  }
}

/** Comment-line detector for Dart / TypeScript. */
function commentFilter(ext) {
  let inBlock = false;
  return (line) => {
    const t = line.trim();
    if (inBlock) {
      if (t.includes("*/")) inBlock = false;
      return true;
    }
    if (t.startsWith("/*")) {
      if (!t.includes("*/")) inBlock = true;
      return true;
    }
    return t.startsWith("//") || t.startsWith("*") || t.startsWith("#");
  };
}

/** Markdown: fenced code blocks are quoted material and are skipped. */
function markdownFilter() {
  let inFence = false;
  return (line) => {
    if (line.trim().startsWith("```")) {
      inFence = !inFence;
      return true;
    }
    return inFence;
  };
}

const hits = [];

async function scanFile(file, isComment) {
  let text;
  try {
    text = await readFile(file, "utf8");
  } catch {
    return;
  }
  if (!text.includes(DASH)) return;
  const lines = text.split("\n");
  const out = [];
  lines.forEach((line, i) => {
    if (!line.includes(DASH)) return;
    if (isComment(line)) return;
    out.push({ line: i + 1, text: line.trim() });
  });
  if (out.length) hits.push({ file: relative(ROOT, file), count: out.length, samples: out.slice(0, 3) });
}

const targets = [
  ["apps", (f) => extname(f) === ".dart" && f.includes("/lib/"), commentFilter(".dart")],
  ["docs/docs", (f) => extname(f) === ".md", markdownFilter()],
];

for (const [dir, accept, isComment] of targets) {
  for await (const file of walk(join(ROOT, dir))) {
    if (accept(file)) await scanFile(file, isComment);
  }
}

hits.sort((a, b) => b.count - a.count);
const total = hits.reduce((n, h) => n + h.count, 0);

if (total === 0) {
  if (!process.argv.includes("--quiet")) console.log("check-copy: no em dashes in app strings or documentation");
  process.exit(0);
}

console.log(`check-copy: ${total} em dash(es) in ${hits.length} file(s)`);
for (const h of hits.slice(0, 20)) {
  console.log(`  ${String(h.count).padStart(3)}  ${h.file}`);
  for (const s of h.samples) console.log(`       ${s.line}: ${s.text.slice(0, 150)}`);
}
if (hits.length > 20) console.log(`  … and ${hits.length - 20} more file(s)`);
console.log("\nReplace each with a full stop, a comma or a colon chosen for the sentence.");
process.exit(1);
