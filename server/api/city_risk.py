"""GET /v1/city-risk.geojson: the public close-pass layer (docs/DATA_PIPELINE.md).
?demo=1 includes demo rides. Open CORS, cacheable for 60 s."""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, os.path.dirname(__file__))
import _store  # noqa: E402


class handler(BaseHTTPRequestHandler):
    def do_GET(self):
        demo = parse_qs(urlparse(self.path).query).get("demo") == ["1"]
        try:
            with _store.connect() as conn:
                body = json.dumps(_store.city_risk(conn, demo), separators=(",", ":")).encode()
        except Exception as e:
            print(f"query failed: {type(e).__name__}: {e}", file=sys.stderr)
            body, code = b'{"error":"database unavailable"}', 503
        else:
            code = 200
        self.send_response(code)
        self.send_header("Content-Type", "application/geo+json")
        self.send_header("Access-Control-Allow-Origin", "*")
        # With test rides, never cached: a stage ride must be on the map at the first refresh.
        self.send_header("Cache-Control", "public, max-age=60" if code == 200 and not demo else "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET")
        self.end_headers()
