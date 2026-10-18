#!/usr/bin/env python3
"""4sight/Front/CityLayers.json, the City of Toronto layers the app's close-pass map draws
under the rider's near misses: protected and painted bike lanes (simplified to ~5 m) and every
cyclist killed or seriously injured 2022 to Oct 2026. From web/data/city/ (City-data work).

  python3 tools/city_app_layers.py
"""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CITY = ROOT / "web/data/city"
OUT = ROOT / "4sight/Front/CityLayers.json"
TOLERANCE_M = 5


def simplify(pts, tol):
    """Douglas-Peucker on lon/lat, distances in metres on a local plane."""
    if len(pts) < 3:
        return pts
    k = math.cos(math.radians(pts[0][1]))
    (ax, ay), (bx, by) = pts[0], pts[-1]
    dx, dy = (bx - ax) * k, by - ay
    norm = math.hypot(dx, dy) or 1e-12
    far, idx = 0.0, 0
    for i, (x, y) in enumerate(pts[1:-1], 1):
        d = abs(dy * (x - ax) * k - dx * (y - ay)) / norm * 111_320
        if d > far:
            far, idx = d, i
    if far <= tol:
        return [pts[0], pts[-1]]
    return simplify(pts[: idx + 1], tol)[:-1] + simplify(pts[idx:], tol)


def main():
    lanes = []
    for f in json.loads((CITY / "bike_lanes.geojson").read_text())["features"]:
        t = f["properties"]["lane_type"]
        if t not in ("protected", "painted"):
            continue
        g = f["geometry"]
        for part in [g["coordinates"]] if g["type"] == "LineString" else g["coordinates"]:
            pts = simplify(part, TOLERANCE_M)
            lanes.append({"t": t, "p": [round(v, 5) for lon, lat in pts for v in (lat, lon)]})
    ksi = [{"lat": round(f["geometry"]["coordinates"][1], 5), "lon": round(f["geometry"]["coordinates"][0], 5),
            "killed": f["properties"]["outcome"] == "killed", "date": f["properties"]["date"],
            "where": f["properties"]["location"]}
           for f in json.loads((CITY / "cyclist_ksi_2022_2026.geojson").read_text())["features"]]
    OUT.write_text(json.dumps({"source": "City of Toronto Open Data and Vision Zero, downloaded 2026-10-17",
                               "lanes": lanes, "ksi": ksi}, separators=(",", ":")))
    print(f"{OUT.relative_to(ROOT)}: {len(lanes)} lane lines, {len(ksi)} KSI, {OUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
