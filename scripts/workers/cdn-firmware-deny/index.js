// Deny cdn.jkbmsr.com/firmware/** at the edge, unconditionally.
//
// WHY (2026-10-13). Firmware is delivered only by the account-gated API
// (api.jkbmsr.com/v1/flash/*), which streams it from the private R2 bucket. The
// Pages origin is clean — a cache-busted request 404s every /firmware/** path,
// the project hostname jkbmsr-releases-1v3.pages.dev 404s, the superseded
// deployments were deleted, and releases/firmware/** was stripped from git —
// yet the *clean* URLs kept returning 200 with pre-cutover content after two
// "Purge Everything"s. The zone has no cache rules and no page rules (only an
// http_request_dynamic_redirect ruleset), so it was an edge-cache quirk keyed
// to the clean path that a zone purge does not clear.
//
// WHY A WORKER. A request that matches a Worker route is answered by this code
// and never reaches the static origin or that cache, so the block does not
// depend on the cache being cleared. A Single Redirects rule cannot do this: it
// can only redirect, never answer 404 — and this zone is on the Free plan,
// where Single Redirects are capped at 10 rules. The same mechanism already
// retires the www and docs hosts on this zone (Workers jkbmsr-www-redirect,
// jkbmsr-docs-redirect), so it is the established pattern here.
//
// SCOPE IS DELIBERATELY NARROW. Only the host+path pair is denied; every other
// request is passed straight through, so /ota/**, /docs/**, /mobile/** and /
// keep working. The host check is defence in depth: the route already limits
// this Worker to cdn.jkbmsr.com/firmware*, but the code is written so that even
// a widened route cannot make it deny a different host's firmware path.
//
// ROLLBACK: delete the route or the Worker — see README.md. No data is
// involved, and firmware delivery is unaffected (it is a different host).
export default {
  async fetch(request) {
    if (isDenied(new URL(request.url))) {
      return new Response("Not Found\n", {
        status: 404,
        headers: {
          "content-type": "text/plain; charset=utf-8",
          // Never let any cache store this decision. A 404 is not cached by
          // default, but the whole failure being fixed here was a cache holding
          // a removed path, so say it explicitly rather than rely on a default.
          "cache-control": "no-store",
        },
      });
    }
    // Unchanged pass-through for everything else at this host.
    return fetch(request);
  },
};

// The firmware namespace on the CDN. Exact and sub-path forms are both denied;
// a lookalike prefix such as /firmware-old is not (it never held firmware).
export function isDenied(url) {
  return (
    url.hostname === "cdn.jkbmsr.com" &&
    (url.pathname === "/firmware" || url.pathname.startsWith("/firmware/"))
  );
}
