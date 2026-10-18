#!/usr/bin/env python3
"""Street segments into Tiger Cloud, then every stored point and near miss re-matched to them.

  DATABASE_URL=... uv run --with 'psycopg[binary]' tools/load_segments.py --source osm
  DATABASE_URL=... uv run --with 'psycopg[binary]' tools/load_segments.py --source city

osm:  named arterials from tools/cache/toronto_streets.json (OpenStreetMap, the streets
      tools/synth_events.py rides on, Ellesmere/Military Trail/Morningside included). Each
      street's ways are chained end to end and cut into ~400 m segments, long enough that a
      segment collects the 2 km of riding the public map asks for. bike lane -> painted, else none.
      (4sight/Front/Streets.json is not used: its roads carry no street names.)
city: data/city/segments.geojson, the City of Toronto file (docs/DATA_PIPELINE.md).

Either way the old segments are replaced, so loading the City file switches the map over.
Data © OpenStreetMap contributors, ODbL; City of Toronto Open Data.
"""
import argparse
import json
import math
import os
from pathlib import Path

import psycopg

ROOT = Path(__file__).resolve().parent.parent
PIECE_M = 400


def metres(a, b):
    k = math.cos(math.radians((a[0] + b[0]) / 2))
    return math.hypot((b[0] - a[0]) * 111_320, (b[1] - a[1]) * 111_320 * k)


def chains(ways):
    """Ways of one street joined at shared ends: lists of (pts [[lat, lon]…], bike)."""
    ends = {}
    for i, w in enumerate(ways):
        for e in (tuple(w["pts"][0]), tuple(w["pts"][-1])):
            ends.setdefault(e, []).append(i)
    used, out = set(), []
    for i in range(len(ways)):
        if i in used:
            continue
        used.add(i)
        run = [(ways[i]["pts"], ways[i]["bike"])]
        for forward in (True, False):        # grow from the tail, then from the head
            while True:
                tip = tuple(run[-1][0][-1] if forward else run[0][0][0])
                nxt = next((j for j in ends.get(tip, []) if j not in used), None)
                if nxt is None:
                    break
                used.add(nxt)
                p = ways[nxt]["pts"]
                if forward:
                    run.append((p if tuple(p[0]) == tip else p[::-1], ways[nxt]["bike"]))
                else:
                    run.insert(0, (p if tuple(p[-1]) == tip else p[::-1], ways[nxt]["bike"]))
        out.append(run)
    return out


def osm_segments():
    ways = json.loads((ROOT / "tools/cache/toronto_streets.json").read_text())
    by_street = {}
    for w in ways:
        by_street.setdefault(w["name"], []).append(w)
    segs, n = [], 0
    for street, ws in sorted(by_street.items()):
        for run in chains(ws):
            piece, length, bike_m = [], 0.0, 0.0
            for k, (pts, bike) in enumerate(run):
                piece += pts if not piece else pts[1:]
                d = sum(metres(a, b) for a, b in zip(pts, pts[1:]))
                length += d
                bike_m += d if bike else 0
                if length >= PIECE_M or k == len(run) - 1:
                    n += 1
                    segs.append({"id": f"osm-{n}", "street": street,
                                 "lane_type": "painted" if bike_m >= length / 2 else "none",
                                 "ward": None, "ward_name": None, "source": "OpenStreetMap",
                                 "coords": [[lon, lat] for lat, lon in piece]})
                    piece, length, bike_m = [], 0.0, 0.0
    return segs


def city_segments():
    gj = json.loads((ROOT / "data/city/segments.geojson").read_text())
    segs = []
    for f in gj["features"]:
        p = f["properties"]
        assert f["geometry"]["type"] == "LineString", p.get("segment_id")
        assert p["lane_type"] in ("protected", "painted", "shared", "none"), p.get("segment_id")
        segs.append({"id": str(p["segment_id"]), "street": p.get("street"), "lane_type": p["lane_type"],
                     "ward": p.get("ward"), "ward_name": p.get("ward_name"),
                     "source": p.get("source", "City of Toronto"), "coords": f["geometry"]["coordinates"]})
    return segs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", choices=["osm", "city"], required=True)
    segs = osm_segments() if ap.parse_args().source == "osm" else city_segments()
    segs = [s for s in segs if len(s["coords"]) >= 2]
    with psycopg.connect(os.environ["DATABASE_URL"], autocommit=True) as conn:
        with conn.transaction():
            conn.execute("DELETE FROM segments")
            with conn.cursor() as cur:
                cur.executemany(
                    "INSERT INTO segments (id, street, lane_type, ward, ward_name, source, geom) "
                    "VALUES (%s, %s, %s, %s, %s, %s, ST_GeogFromText(%s))",
                    [(s["id"], s["street"], s["lane_type"], s["ward"], s["ward_name"], s["source"],
                      "SRID=4326;LINESTRING(" + ",".join(f"{x} {y}" for x, y in s["coords"]) + ")") for s in segs])
            for table in ("ride_points", "near_misses"):
                conn.execute(f"UPDATE {table} SET segment_id = match_segment(geom)")
        for view in ("segment_km_hourly", "segment_passes_hourly"):
            conn.execute(f"CALL refresh_continuous_aggregate('{view}', NULL, NULL)")
        matched = conn.execute("SELECT count(segment_id), count(*) FROM ride_points").fetchone()
    print(f"{len(segs)} segments loaded; {matched[0]} of {matched[1]} ride points on a segment")


if __name__ == "__main__":
    main()
