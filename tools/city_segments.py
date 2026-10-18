#!/usr/bin/env python3
"""data/city/segments.geojson, the City of Toronto segments file in docs/DATA_PIPELINE.md, from
the City-data work's cleaned files in web/data/city/ plus OpenStreetMap streets.

  python3 tools/city_segments.py

- Every line of the City Cycling Network (bike_lanes.geojson) is a segment. lane_type per the
  contract: cycle tracks and multi-use trails -> protected, bike lanes -> painted, sharrows and
  signed routes -> shared. The City's own fields are kept untouched under "city".
- Streets riders use that are not in the network -> none: the OSM arterial pieces from
  tools/load_segments.py whose middle is more than 20 m from any City line.
- ward / ward_name from the City's 25-ward boundaries, by the segment's middle.
The City file has no stable segment id, so ids are city-<row>-<part> in file order.
City of Toronto Open Data; © OpenStreetMap contributors, ODbL.
"""
import json
import math
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from load_segments import osm_segments  # noqa: E402

CITY = ROOT / "web/data/city"
OUT = ROOT / "data/city/segments.geojson"
LANE = {"protected": "protected", "trail": "protected", "painted": "painted", "shared": "shared"}
NEAR_M = 20
CELL = 0.001  # degrees, ~100 m


def xy(p, lat0):
    """lon/lat -> metres on a local plane; plenty across one city."""
    return p[0] * 111_320 * math.cos(math.radians(lat0)), p[1] * 111_320


def seg_dist(p, a, b):
    ax, ay, bx, by = a[0] - p[0], a[1] - p[1], b[0] - p[0], b[1] - p[1]
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, -(ax * dx + ay * dy) / (dx * dx + dy * dy or 1)))
    return math.hypot(ax + t * dx, ay + t * dy)


def middle(coords):
    """The point half way along a line, by length."""
    d = [0.0]
    for a, b in zip(coords, coords[1:]):
        d.append(d[-1] + math.dist(a, b))
    half = d[-1] / 2
    i = max(k for k in range(len(d)) if d[k] <= half)
    if i == len(coords) - 1:
        return coords[-1]
    f = (half - d[i]) / ((d[i + 1] - d[i]) or 1)
    return [coords[i][0] + (coords[i + 1][0] - coords[i][0]) * f, coords[i][1] + (coords[i + 1][1] - coords[i][1]) * f]


def inside(p, rings):
    """Even-odd point in polygon, outer ring and holes alike."""
    hit = False
    for ring in rings:
        for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1]):
            if (y1 > p[1]) != (y2 > p[1]) and p[0] < x1 + (p[1] - y1) * (x2 - x1) / (y2 - y1):
                hit = not hit
    return hit


def main():
    lanes = json.loads((CITY / "bike_lanes.geojson").read_text())["features"]
    wards = json.loads((CITY / "wards.geojson").read_text())["features"]
    polys = [(int(w["properties"]["ward"]), w["properties"]["ward_name"],
              w["geometry"]["coordinates"] if w["geometry"]["type"] == "Polygon" else
              [r for poly in w["geometry"]["coordinates"] for r in poly]) for w in wards]

    def ward_of(p):
        return next(((n, name) for n, name, rings in polys if inside(p, rings)), (None, None))

    feats, grid, lat0 = [], defaultdict(list), 43.7
    for i, f in enumerate(lanes):
        g = f["geometry"]
        parts = [g["coordinates"]] if g["type"] == "LineString" else g["coordinates"]
        p = f["properties"]
        assert p["lane_type"] in LANE, p
        for k, coords in enumerate(c for c in parts if len(c) >= 2):
            ward, name = ward_of(middle(coords))
            feats.append({"type": "Feature", "geometry": {"type": "LineString", "coordinates": coords},
                          "properties": {"segment_id": f"city-{i}-{k}", "street": p.get("street"),
                                         "lane_type": LANE[p["lane_type"]], "ward": ward, "ward_name": name,
                                         "source": "City of Toronto Cycling Network", "city": p}})
            pts = [xy(c, lat0) for c in coords]
            for a, b in zip(pts, pts[1:]):
                for cx in range(int(min(a[0], b[0]) // 100) - 1, int(max(a[0], b[0]) // 100) + 2):
                    for cy in range(int(min(a[1], b[1]) // 100) - 1, int(max(a[1], b[1]) // 100) + 2):
                        grid[(cx, cy)].append((a, b))

    kept = 0
    for s in osm_segments():
        mid = middle(s["coords"])
        m = xy(mid, lat0)
        near = grid.get((int(m[0] // 100), int(m[1] // 100)), [])
        if any(seg_dist(m, a, b) <= NEAR_M for a, b in near):
            continue                       # the City line is the segment here
        ward, name = ward_of(mid)
        feats.append({"type": "Feature", "geometry": {"type": "LineString", "coordinates": s["coords"]},
                      "properties": {"segment_id": s["id"], "street": s["street"], "lane_type": "none",
                                     "ward": ward, "ward_name": name, "source": "OpenStreetMap", "city": None}})
        kept += 1

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"type": "FeatureCollection", "features": feats}, separators=(",", ":")))
    by = defaultdict(int)
    for f in feats:
        by[f["properties"]["lane_type"]] += 1
    print(f"{OUT.relative_to(ROOT)}: {len(feats)} segments {dict(by)}; {kept} OSM streets without a City line; "
          f"{sum(f['properties']['ward'] is None for f in feats)} outside every ward")


if __name__ == "__main__":
    main()
