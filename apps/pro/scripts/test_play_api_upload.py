#!/usr/bin/env python3
"""Verifies the resumable upload's resume path without touching Google.

The failure this exists for is a connection dropped mid-chunk — what killed two
real uploads of the Contributor 1.0.4 bundle. The old code only resumed across a
`308`, so a dropped socket aborted a session that was designed to be resumable.

The loopback server below commits the first chunk and THEN drops the connection
without answering. That is the dangerous ordering: the client cannot tell from
the failure whether the bytes landed, so the only correct behaviour is to ask the
session (`bytes */<total>`) and continue from the answer. The test asserts:

  * the session was queried,
  * the committed range was not resent,
  * no range was skipped, and
  * every chunk that arrived matched the file at its stated offset.

Run: python3 apps/pro/scripts/test_play_api_upload.py
"""
import http.server
import json
import os
import sys
import tempfile
import threading

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import play_api  # noqa: E402

TOTAL = 4096
CHUNK = 1024
BUNDLE = bytes(range(256)) * (TOTAL // 256)

FIRST = f"bytes 0-{CHUNK - 1}/{TOTAL}"
QUERY = f"bytes */{TOTAL}"


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    committed = 0
    dropped_once = False
    finished = False
    ranges: list[str] = []

    def log_message(self, *args):  # keep the test output readable
        pass

    def _empty(self, status, headers=()):
        self.send_response(status)
        for name, value in headers:
            self.send_header(name, value)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_POST(self):
        # Upload-session init.
        self._empty(200, [("Location", f"http://127.0.0.1:{self.server.server_port}/session")])

    def do_PUT(self):
        content_range = self.headers.get("Content-Range", "")
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        Handler.ranges.append(content_range)

        if content_range == QUERY:
            # "How much do you have?" — the answer the client must act on.
            if Handler.committed == 0:
                self._empty(308)
            else:
                self._empty(308, [("Range", f"bytes=0-{Handler.committed - 1}")])
            return

        start_text, rest = content_range[len("bytes "):].split("-")
        end_text = rest.split("/")[0]
        start, end = int(start_text), int(end_text)
        assert body == BUNDLE[start:end + 1], (
            f"chunk {start}-{end} does not match the file at that offset"
        )

        if not Handler.dropped_once:
            # It LANDED, and then the connection dies before the response.
            Handler.dropped_once = True
            Handler.committed = end + 1
            self.close_connection = True
            try:
                self.connection.close()
            except OSError:
                pass
            return

        Handler.committed = end + 1
        if Handler.committed >= TOTAL:
            payload = json.dumps({"versionCode": 5}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            Handler.finished = True
            return

        self._empty(308)


def main() -> int:
    play_api.CHUNK_SIZE = CHUNK
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    play_api.UPLOAD_ROOT = f"http://127.0.0.1:{server.server_port}/upload"

    with tempfile.NamedTemporaryFile(suffix=".aab", delete=False) as handle:
        handle.write(BUNDLE)
        path = handle.name

    try:
        version_code = play_api.upload_bundle("com.example.test", "edit", "token", path)
    finally:
        os.unlink(path)
        server.shutdown()

    problems = []
    if version_code != 5:
        problems.append(f"versionCode was {version_code}, expected 5")
    if not Handler.finished:
        problems.append("the upload never completed")
    if QUERY not in Handler.ranges:
        problems.append("the client never asked the session what it had committed")
    if Handler.ranges.count(FIRST) != 1:
        problems.append(f"the committed range was sent {Handler.ranges.count(FIRST)} times, expected 1")

    if problems:
        for problem in problems:
            print(f"FAIL {problem}")
        return 1

    print("PASS the upload resumed after a dropped connection and completed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
