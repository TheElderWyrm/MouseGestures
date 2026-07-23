#!/usr/bin/env python3
"""Local dev server for the MouseGestures style & color test site.

Serves the PROJECT ROOT (the parent of this directory) so the test page can
load the live production site (/Website/index.html) in same-origin iframes
and restyle it in place — no copies that drift out of date.

Adds the same tiny JSON API as Website-test/serve.py so notes persist to
disk in THIS directory:

    GET  /api/notes        -> {} or the saved notes object
    POST /api/notes        -> body {"key": "...", "text": "..."}, merges
                               into notes.json and writes it to disk

Usage: python3 serve.py [port]   (default port 8001)
Then open http://127.0.0.1:8001/Website-style-test/
"""
import http.server
import json
import os
import socketserver
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
NOTES_PATH = os.path.join(HERE, "notes.json")
MAX_BODY_BYTES = 1_000_000


def load_notes():
    if not os.path.exists(NOTES_PATH):
        return {}
    try:
        with open(NOTES_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return {}


def save_notes(notes):
    tmp_path = NOTES_PATH + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(notes, f, indent=2, sort_keys=True)
    os.replace(tmp_path, NOTES_PATH)


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def do_GET(self):
        if self.path == "/api/notes":
            self._send_json(200, load_notes())
            return
        if self.path in ("/", ""):
            self.send_response(302)
            self.send_header("Location", "/Website-style-test/")
            self.end_headers()
            return
        super().do_GET()

    def do_POST(self):
        if self.path != "/api/notes":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", 0))
        if length <= 0 or length > MAX_BODY_BYTES:
            self.send_error(413, "Note too large")
            return
        raw = self.rfile.read(length)
        try:
            payload = json.loads(raw.decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            self.send_error(400, "Invalid JSON")
            return
        key = payload.get("key")
        text = payload.get("text", "")
        if not isinstance(key, str) or not key or not isinstance(text, str):
            self.send_error(400, "Expected {key, text} strings")
            return
        notes = load_notes()
        notes[key] = text
        save_notes(notes)
        self._send_json(200, {"ok": True})

    def _send_json(self, status, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8001
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer(("127.0.0.1", port), Handler) as httpd:
        print("Serving {} at http://127.0.0.1:{}/Website-style-test/  (notes -> {})".format(ROOT, port, NOTES_PATH))
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
