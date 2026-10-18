#!/usr/bin/env python3
"""tools/synth_events.py's modelled rides into Tiger Cloud, with synthetic = true, through
the same insert the server uses for real uploads (server/api/_store.py).

  DATABASE_URL=... uv run --with 'psycopg[binary]' tools/load_synthetic.py [--dir data/synthetic]

Replaces any synthetic rows already loaded, so it can be run again. Run
tools/load_segments.py first so the points are matched to streets as they go in.
"""
import argparse
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "server" / "api"))
import _store  # noqa: E402


def ts(iso):
    return datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="data/synthetic")
    d = ROOT / ap.parse_args().dir
    if not (d / "rides.jsonl").exists():
        subprocess.run([sys.executable, str(ROOT / "tools/synth_events.py"), "--out", str(d)], check=True)
    rides = [json.loads(line) for line in open(d / "rides.jsonl") if line.strip()]
    events = [json.loads(line) for line in open(d / "events.jsonl") if line.strip()]
    assert all(r["synthetic"] for r in rides) and all(e["synthetic"] for e in events)

    # The generator writes events apart from their rides; each belongs to the ride on the
    # same street whose time span holds it.
    spans = [(r["street"], ts(r["points"][0][2]), ts(r["points"][-1][2])) for r in rides]
    by_ride = {i: [] for i in range(len(rides))}
    for e in events:
        t = ts(e["timestamp"])
        i = next(i for i, (s, a, b) in enumerate(spans) if s == e["street"] and a <= t <= b)
        right = e["right_level"] > e["left_level"]
        by_ride[i].append({"t": t, "lat": e["lat"], "lon": e["lon"], "cls": e["cls"],
                           "level": max(e["left_level"], e["right_level"]), "side": "R" if right else "L",
                           "gap_m": e["gap_m"], "ttc_s": e["ttc_seconds"], "speed": e["speed"]})

    with _store.connect() as conn:
        with conn.transaction():
            for table in ("near_misses", "ride_points", "rides"):
                conn.execute(f"DELETE FROM {table} WHERE synthetic")
        for i, r in enumerate(rides):
            pts = [(ts(t), lat, lon, 0.0) for lat, lon, t in r["points"]]
            _store.insert_ride(conn, {"install": "synthetic", "demo": False, "started": pts[0][0],
                                      "ended": pts[-1][0], "points": pts, "events": by_ride[i]}, synthetic=True)
        conn.commit()
        conn.autocommit = True
        for view in ("segment_km_hourly", "segment_passes_hourly"):
            conn.execute(f"CALL refresh_continuous_aggregate('{view}', NULL, NULL)")
    print(f"{len(rides)} synthetic rides, {len(events)} close passes loaded")


if __name__ == "__main__":
    main()
