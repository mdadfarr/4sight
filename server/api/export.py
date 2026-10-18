"""GET /v1/streets.csv and /v1/wards.csv: the public data as spreadsheets. Open CORS, cached 60 s."""
import os
import sys
from http.server import BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, os.path.dirname(__file__))
import _store  # noqa: E402


class handler(BaseHTTPRequestHandler):
    def do_GET(self):
        which = (parse_qs(urlparse(self.path).query).get("t") or [""])[0]
        try:
            with _store.connect() as conn:
                body, code = _store.export_csv(conn, which).encode(), 200
        except KeyError:
            body, code = b"unknown export\n", 404
        except Exception as e:
            print(f"export failed: {type(e).__name__}: {e}", file=sys.stderr)
            body, code = b"database unavailable\n", 503
        self.send_response(code)
        self.send_header("Content-Type", "text/csv; charset=utf-8" if code == 200 else "text/plain")
        if code == 200:
            self.send_header("Content-Disposition", f'attachment; filename="4sight-{which}.csv"')
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "public, max-age=60" if code == 200 else "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
