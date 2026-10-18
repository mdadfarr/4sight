"""POST /v1/rides: one finished ride from the front phone (docs/DATA_PIPELINE.md)."""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler

sys.path.insert(0, os.path.dirname(__file__))
import _store  # noqa: E402


class handler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            n = -1
        if n < 0 or n > _store.MAX_BODY:
            return self._reply(413, {"error": "body over 1 MB"})
        try:
            ride = _store.validate(self.rfile.read(n))
        except _store.Invalid as e:
            return self._reply(413 if e.too_large else 400, {"error": str(e)})
        try:
            with _store.connect() as conn:
                if _store.rate_limited(conn, ride["install"]):
                    return self._reply(429, {"error": "at most 30 rides per hour"})
                ride_id = _store.insert_ride(conn, ride)
        except Exception as e:  # the app keeps the ride and retries on 5xx
            print(f"insert failed: {type(e).__name__}: {e}", file=sys.stderr)
            return self._reply(503, {"error": "database unavailable"})
        self._reply(200, {"ride_id": ride_id, "events": len(ride["events"])})

    def _reply(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
