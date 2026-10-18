"""Both endpoints on one local port, for the simulator before a deploy.
  DATABASE_URL=... uv run --with 'psycopg[binary]' server/dev.py [port=8787]"""
import os
import sys
from http.server import ThreadingHTTPServer

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "api"))
from city_risk import handler as CityRisk  # noqa: E402
from export import handler as Export  # noqa: E402
from rides import handler as Rides  # noqa: E402


class Dev(Rides, CityRisk):
    def do_POST(self):
        if self.path == "/v1/rides":
            return Rides.do_POST(self)
        self.send_error(404)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/v1/city-risk.geojson":
            return CityRisk.do_GET(self)
        if path in ("/v1/streets.csv", "/v1/wards.csv"):
            self.path = "/api/export?t=" + path[4:-4]
            return Export.do_GET(self)
        self.send_error(404)


port = int(sys.argv[1]) if len(sys.argv) > 1 else 8787
print(f"http://localhost:{port}/v1/city-risk.geojson")
ThreadingHTTPServer(("127.0.0.1", port), Dev).serve_forever()
