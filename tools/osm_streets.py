"""Download the streets, sidewalks, buildings and parks of one area from OpenStreetMap
and write the compact file the front phone draws its map from (4sight/Front/Streets.json).

Bundled rather than fetched on the bike: the public Overpass servers took 30 s and
returned 500/502 on and off when this was written, which is no way to draw a road.

    uv run tools/osm_streets.py                       # UTSC / Pan Am Centre, Scarborough
    uv run tools/osm_streets.py --bbox S,W,N,E --out path

Output: {"origin":[lat,lon], "ways":[{"k":kind, "w":width_m, "n":lanes, "one":0|1,
"bike":0|1, "sw":bits 1=left 2=right of the way's direction,
"p":[e0,n0,e1,n1,...]}]} with points in decimetres east/north of origin.
Data © OpenStreetMap contributors, ODbL.
"""
import argparse
import json
import math
import sys
import time
import urllib.parse
import urllib.request

MIRRORS = ["https://overpass-api.de/api/interpreter",
           "https://overpass.kumi.systems/api/interpreter"]
UA = "4sight-hackathon/0.1 (bike safety prototype)"

# Carriageway width when OSM has no lanes/width tag, metres.
ROAD_WIDTH = {"motorway": 11, "trunk": 10, "primary": 10, "secondary": 9, "tertiary": 7.5,
              "unclassified": 6.5, "residential": 6.5, "living_street": 5, "service": 4.5,
              "motorway_link": 4.5, "trunk_link": 4.5, "primary_link": 4.5,
              "secondary_link": 4.5, "tertiary_link": 4.5}
PATHS = {"footway", "path", "cycleway", "pedestrian", "steps", "track", "bridleway"}


def fetch(query: str) -> dict:
    body = urllib.parse.urlencode({"data": query}).encode()
    for attempt in range(6):
        url = MIRRORS[attempt % len(MIRRORS)]
        try:
            req = urllib.request.Request(url, data=body, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.load(r)
        except Exception as e:  # flaky public servers: next mirror, back off
            print(f"{url}: {e}", file=sys.stderr)
            time.sleep(5 * (attempt + 1))
    sys.exit("Overpass unreachable")


def classify(t: dict):
    """(kind, width, lanes) or None to skip."""
    if "building" in t:
        return "building", 0, 0
    if t.get("leisure") in ("park", "pitch", "garden") or t.get("landuse") in ("grass", "recreation_ground"):
        return "park", 0, 0
    h = t.get("highway")
    if h in ROAD_WIDTH:
        try:
            lanes = int(t.get("lanes", "0").split(";")[0])
        except ValueError:
            lanes = 0
        try:
            width = float(t.get("width", "0").split()[0])
        except ValueError:
            width = 0
        width = width or (lanes * 3.3 if lanes else ROAD_WIDTH[h])
        return "road", width, lanes
    if h in PATHS:
        if t.get("footway") == "crossing" or t.get("cycleway") == "crossing":
            return "crossing", 3.0, 0
        return "path", 1.5 if h == "steps" else 2.0, 0
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bbox", default="43.772,-79.212,43.798,-79.168", help="S,W,N,E")
    ap.add_argument("--out", default="4sight/Front/Streets.json")
    a = ap.parse_args()
    s, w, n, e = (float(v) for v in a.bbox.split(","))
    bb = f"({s},{w},{n},{e})"
    q = (f"[out:json][timeout:120];(way[highway]{bb};way[building]{bb};"
         f"way[leisure~\"^(park|pitch|garden)$\"]{bb};way[landuse~\"^(grass|recreation_ground)$\"]{bb};);out geom;")
    data = fetch(q)

    lat0, lon0 = (s + n) / 2, (w + e) / 2
    m_lat, m_lon = 111_320.0, 111_320.0 * math.cos(math.radians(lat0))
    ways = []
    for el in data["elements"]:
        t = el.get("tags", {})
        c = classify(t)
        if not c or "geometry" not in el:
            continue
        kind, width, lanes = c
        pts = []
        for g in el["geometry"]:
            pts += [round((g["lon"] - lon0) * m_lon * 10), round((g["lat"] - lat0) * m_lat * 10)]
        way = {"k": kind, "p": pts}
        if kind in ("road", "path", "crossing"):
            way["w"] = round(width, 1)
        if kind == "road":
            way["n"] = lanes
            way["one"] = int(t.get("oneway") == "yes")
            way["bike"] = int(any(t.get(k) in ("lane", "track") for k in
                                  ("cycleway", "cycleway:both", "cycleway:left", "cycleway:right")))
            # Sidewalks tagged on the road rather than mapped as their own ways
            # ("separate" means they are, and get drawn from that way instead).
            sw = t.get("sidewalk") or t.get("sidewalk:both")
            left = sw in ("both", "left") or t.get("sidewalk:left") == "yes"
            right = sw in ("both", "right") or t.get("sidewalk:right") == "yes"
            if left or right:
                way["sw"] = int(left) | int(right) << 1
        ways.append(way)
    # Draw order is the file order: parks, paths, crossings, roads, buildings on top.
    order = {"park": 0, "path": 1, "crossing": 2, "road": 3, "building": 4}
    ways.sort(key=lambda x: order[x["k"]])
    assert ways, "no ways in bbox"
    with open(a.out, "w") as f:
        json.dump({"origin": [lat0, lon0], "ways": ways}, f, separators=(",", ":"))
    kinds = {k: sum(1 for x in ways if x["k"] == k) for k in order}
    print(f"{a.out}: {len(ways)} ways {kinds}")


if __name__ == "__main__":
    main()
