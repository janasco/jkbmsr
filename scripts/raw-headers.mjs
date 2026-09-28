#!/usr/bin/env node
/**
 * raw-headers.mjs — read response headers over a RAW socket, one by one, and
 * report any header that appears more than once.
 *
 * WHY A RAW SOCKET AND NOT A CLIENT
 *   HTTP/1.1 joins repeated response header fields with ", " before a client
 *   ever sees them. So a client library cannot distinguish
 *     content-type: application/atom+xml; charset=utf-8
 *   from
 *     content-type: application/atom+xml; charset=utf-8, application/rss+xml; charset=utf-8
 *   — and that is exactly how the two-media-type bug survived in this project.
 *   `dist/` was correct; only the edge was wrong; and every client-side check
 *   said "one content-type". The bytes on the wire are the only place the
 *   difference exists, so that is where the check has to be.
 *
 * `server-timing` legitimately appears twice on Cloudflare's edge (cache status
 * plus edge/origin timings) and is not a `_headers` append, so it is excluded
 * by name and the exclusion is printed rather than applied silently.
 *
 * Usage: node raw-headers.mjs <host:port> <path> [<path> ...]
 *        node raw-headers.mjs --scheme https jkbmsr.com / /feed/
 * Exit: 0 no header WE ship is duplicated, 1 one is, 2 could not read.
 */
import net from 'node:net';
import tls from 'node:tls';
import process from 'node:process';

/** Headers Cloudflare itself sets, which may legitimately repeat. */
const PLATFORM_HEADERS = new Set(['server-timing', 'set-cookie', 'www-authenticate']);

const argv = process.argv.slice(2);

/**
 * DETERMINISTIC SELF-TEST. A negative result is only evidence if the instrument
 * has been seen to produce a positive one, and the live control for this is not
 * dependable: Cloudflare emits its two `Server-Timing` fields intermittently
 * (measured on this host — 2 repeats on three consecutive responses at 02:03, 0
 * repeats on five consecutive responses at 02:08, from two independent raw-socket
 * implementations that agreed with each other at each moment). So the control is
 * served locally and is always the same.
 *
 * Serves one response containing a header WE ship, twice, and a platform header,
 * twice. The first must be reported as a duplicate; the second must be excluded.
 * A tool that reported neither, or both, fails.
 */
async function selfTest() {
  const server = net.createServer((socket) => {
    socket.end(
      'HTTP/1.1 200 OK\r\n' +
        'content-type: text/html; charset=utf-8\r\n' +
        'x-test: first\r\n' +
        'x-test: second\r\n' +
        'server-timing: cfCacheStatus;desc="HIT"\r\n' +
        'server-timing: cfEdge;dur=1,cfOrigin;dur=2\r\n' +
        'content-length: 0\r\n' +
        'connection: close\r\n\r\n'
    );
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const { port } = server.address();
  let sawOurs = false;
  let sawPlatform = false;
  const seen = [];
  try {
    const r = await readOneAgainst(port, '/');
    const byName = new Map();
    for (const [n, v] of r.headers) {
      if (!byName.has(n)) byName.set(n, []);
      byName.get(n).push(v);
    }
    for (const [n, vs] of byName) {
      if (vs.length < 2) continue;
      seen.push(`${n} x${vs.length}`);
      if (PLATFORM_HEADERS.has(n)) sawPlatform = true;
      else sawOurs = true;
    }
  } finally {
    // `server.close(cb)` waits for every connection to finish, and the one this
    // test just made does not: the client called `destroy()`, which leaves the
    // server's side half-open, so the callback never fires and node exits 13
    // with "unsettled top-level await". That was the first version, and it is
    // worth recording because it presents as "the self-test hangs" and invites a
    // reader to conclude the socket code is at fault. Force the connections
    // shut, and do not wait on close.
    server.closeAllConnections?.();
    server.close();
    server.unref();
  }
  const problems = [];
  if (!sawOurs) problems.push('a duplicated header we ship was NOT reported — the tool is blind to the failure it exists to catch');
  if (!sawPlatform) problems.push('a duplicated platform header was not recognised as a platform header, so the exclusion is untested');
  if (problems.length) {
    process.stdout.write(`   ${problems.map((p) => `FAIL: ${p}`).join('\n   ')}\n`);
    process.exit(1);
  }
  process.stdout.write(`   ok    control: a locally served response with 2 repeated headers (${seen.join(', ')}) — ours reported, platform excluded\n`);
  process.stdout.write('         This is what makes the negative below mean something. Read it as: no duplicate of ours,\n');
  process.stdout.write('         with an instrument demonstrated to report one when there is one.\n');
}

function readOneAgainst(port, p) {
  return new Promise((resolve, reject) => {
    const socket = net.connect({ host: '127.0.0.1', port });
    let buf = Buffer.alloc(0);
    let done = false;
    const fail = (e) => {
      if (done) return;
      done = true;
      socket.destroy();
      reject(e);
    };
    socket.setTimeout(10000, () => fail(new Error('timeout')));
    socket.on('error', fail);
    socket.on('connect', () => socket.write(`GET ${p} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n`));
    socket.on('data', (chunk) => {
      buf = Buffer.concat([buf, chunk]);
      const end = buf.indexOf('\r\n\r\n');
      if (end !== -1 && !done) {
        done = true;
        socket.destroy();
        const lines = buf.slice(0, end).toString('latin1').split('\r\n');
        const headers = [];
        for (const line of lines.slice(1)) {
          const i = line.indexOf(':');
          if (i > 0) headers.push([line.slice(0, i).trim().toLowerCase(), line.slice(i + 1).trim()]);
        }
        resolve({ status: lines[0], headers });
      }
    });
  });
}

if (argv[0] === '--self-test') {
  await selfTest();
  process.exit(0);
}

let scheme = 'http';
let rest = argv;
if (argv[0] === '--scheme') {
  scheme = argv[1];
  rest = argv.slice(2);
}
const [authority, ...paths] = rest;
if (!authority || paths.length === 0) {
  process.stdout.write('usage: raw-headers.mjs [--scheme https] <host:port> <path> [...]\n');
  process.exit(2);
}
const secure = scheme === 'https';

/** Read one response, returning its status line and headers as an ordered list. */
function readOne(path) {
  return new Promise((resolve, reject) => {
    const socket = secure
      ? tls.connect({ host: authority.split(':')[0], port: Number(authority.split(':')[1] || 443), servername: authority.split(':')[0] })
      : net.connect({ host: authority.split(':')[0], port: Number(authority.split(':')[1] || 80) });
    let buf = Buffer.alloc(0);
    let done = false;
    const fail = (e) => {
      if (done) return;
      done = true;
      socket.destroy();
      reject(e);
    };
    socket.setTimeout(20000, () => fail(new Error('timeout')));
    socket.on('error', fail);
    socket.on(authority && secure ? 'secureConnect' : 'connect', () => {
      socket.write(`GET ${path} HTTP/1.1\r\nHost: ${authority}\r\nUser-Agent: raw-headers/1.0\r\nAccept: */*\r\nConnection: close\r\n\r\n`);
    });
    socket.on('data', (chunk) => {
      buf = Buffer.concat([buf, chunk]);
      const end = buf.indexOf('\r\n\r\n');
      // Header block complete. Do not wait for the body: it can be large and it
      // is not what is being measured.
      if (end !== -1 && !done) {
        done = true;
        const head = buf.slice(0, end).toString('latin1');
        socket.destroy();
        const lines = head.split('\r\n');
        const status = lines[0];
        const headers = [];
        for (const line of lines.slice(1)) {
          const i = line.indexOf(':');
          if (i > 0) headers.push([line.slice(0, i).trim().toLowerCase(), line.slice(i + 1).trim()]);
        }
        resolve({ status, headers });
      }
    });
  });
}

let bad = 0;
let totalHeaders = 0;
let pathsRead = 0;
const platformSeen = new Map();

for (const p of paths) {
  let r;
  try {
    r = await readOne(p);
  } catch (e) {
    process.stdout.write(`   ERR  ${p}  ${e.message}\n`);
    bad += 1;
    continue;
  }
  pathsRead += 1;
  const byName = new Map();
  for (const [n, v] of r.headers) {
    totalHeaders += 1;
    if (!byName.has(n)) byName.set(n, []);
    byName.get(n).push(v);
  }
  const dupes = [...byName.entries()].filter(([, vs]) => vs.length > 1);
  const ours = dupes.filter(([n]) => !PLATFORM_HEADERS.has(n));
  const theirs = dupes.filter(([n]) => PLATFORM_HEADERS.has(n));
  for (const [n, vs] of theirs) {
    platformSeen.set(n, (platformSeen.get(n) || 0) + 1);
    process.stdout.write(`         CONTROL — a repeat this tool CAN see: ${n} x${vs.length} (platform, excluded)\n`);
  }
  const flag = ours.length ? 'DUP!' : 'ok  ';
  process.stdout.write(
    `   ${flag}  ${r.status.padEnd(16)} ${String(byName.size).padStart(2)} distinct / ${String(r.headers.length).padStart(2)} raw header fields  ${p}\n`
  );
  for (const [n, vs] of ours) {
    process.stdout.write(`         DUPLICATED (ours): ${n}: ${vs.map((v) => `"${v}"`).join('  |  ')}\n`);
  }
}

const [host, portText] = authority.split(':');
const shownPort = portText || (secure ? '443' : '80');
process.stdout.write(`\n   ${pathsRead} path(s), ${totalHeaders} raw header field(s) read over a raw ${scheme.toUpperCase()} socket to ${host}:${shownPort}.\n`);
process.stdout.write(
  `   Platform headers excluded by name: ${
    platformSeen.size
      ? [...platformSeen].map(([n, c]) => `${n} (repeated on ${c} response(s))`).join(', ')
      : 'none seen in this run — so on this endpoint the run proves the absence of duplicates but not that the tool can SEE one. Repeat the run, or point it at a host that repeats a header, before reading the result as assurance.'
  }\n`
);
process.exit(bad ? 1 : 0);
