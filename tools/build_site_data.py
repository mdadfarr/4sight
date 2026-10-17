#!/usr/bin/env python3
"""Real rides from the phones plus synthetic ones -> the website's data files.

  python3 tools/build_site_data.py [--real data/real] [--synthetic data/synthetic] [--out web/data]

Real input: what the rear phone shares from Documents/ — events.jsonl (one near-miss per
line), gps-*.jsonl (every ride) and ride-*.jsonl (rides recorded with video). Synthetic input:
tools/synth_events.py's output, generated here if missing.

Writes web/data/events.geojson, rides.geojson and summary.json. Every feature carries
"synthetic": true|false. Nothing identifying a rider leaves: no track ids, no device names,
and the first and last 200 m of each real ride are cut so a ride never starts at a home.
"""
import argparse
import glob
import json
import math
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

HERE = Path(__file__).resolve().parent
TORONTO = ZoneInfo("America/Toronto")
PRIVACY_M = 200
SNAP_M = 35
CELL = 0.002  # degrees, ~200 m: grid for snapping to streets


def metres(a, b):
    k = math.cos(math.radians((a[0] + b[0]) / 2))
    return math.hypot((b[0] - a[0]) * 111_320, (b[1] - a[1]) * 111_320 * k)


def read_jsonl(path):
    with open(path) as f:
        return [json.loads(line) for line in f if line.strip()]


def local_hour(iso):
    if not iso:
        return None
    t = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    if t.tzinfo is None:
        t = t.replace(tzinfo=timezone.utc)
    return t.astimezone(TORONTO).hour


class Snapper:
    """Nearest cached street segment within SNAP_M metres: its name and bike lane flag."""

    def __init__(self, ways):
        self.grid = defaultdict(list)
        for w in ways:
            for a, b in zip(w["pts"], w["pts"][1:]):
                for la in range(int(min(a[0], b[0]) / CELL) - 1, int(max(a[0], b[0]) / CELL) + 2):
                    for lo in range(int(min(a[1], b[1]) / CELL) - 1, int(max(a[1], b[1]) / CELL) + 2):
                        self.grid[(la, lo)].append((a, b, w["name"], w["bike"]))

    def snap(self, lat, lon):
        best = (SNAP_M, None, None)
        k = math.cos(math.radians(lat))
        for a, b, name, bike in self.grid.get((int(lat / CELL), int(lon / CELL)), ()):
            ax, ay = (a[1] - lon) * k * 111_320, (a[0] - lat) * 111_320
            bx, by = (b[1] - lon) * k * 111_320, (b[0] - lat) * 111_320
            dx, dy = bx - ax, by - ay
            l2 = dx * dx + dy * dy
            t = min(max(-(ax * dx + ay * dy) / l2, 0), 1) if l2 else 0
            d = math.hypot(ax + dx * t, ay + dy * t)
            if d < best[0]:
                best = (d, name, bike)
        return best[1], best[2]


def trim_ends(pts, m):
    """Drops the first and last m metres of a track."""
    def cut(p):
        acc = 0.0
        for i in range(1, len(p)):
            acc += metres(p[i - 1][:2], p[i][:2])
            if acc >= m:
                return p[i:]
        return []
    front = cut(pts)
    return list(reversed(cut(list(reversed(front)))))


def real_rides(paths, snapper):
    """GPS tracks -> one piece per run of points on the same street."""
    pieces = []
    for path in paths:
        fixes = [r for r in read_jsonl(path)
                 if r.get("lat") is not None and r.get("lon") is not None and (r.get("acc") or 0) <= 30]
        fixes.sort(key=lambda r: r.get("t", 0))
        pts = trim_ends([(r["lat"], r["lon"], r.get("time")) for r in fixes], PRIVACY_M)
        if len(pts) < 2:
            continue
        run, key = [pts[0]], snapper.snap(pts[0][0], pts[0][1])
        for p in pts[1:] + [None]:
            k = snapper.snap(p[0], p[1]) if p else None
            if p and k == key:
                run.append(p)
                continue
            if p:
                run.append(p)  # share the boundary point so pieces join up
            if len(run) > 1:
                km = sum(metres(run[i - 1][:2], run[i][:2]) for i in range(1, len(run))) / 1000
                pieces.append({"street": key[0] or "Other streets", "bike_lane": bool(key[1]), "km": km,
                               "km_bike": km if key[1] else 0.0, "hour": local_hour(run[0][2]),
                               "synthetic": False, "coords": [[q[1], q[0]] for q in run]})
            run, key = [p] if p else [], k
    return pieces


def real_events(paths, snapper):
    out = []
    for path in paths:
        for e in read_jsonl(path):
            level = max(e.get("left_level", 0), e.get("right_level", 0))
            if level < 2 or e.get("lat") is None or e.get("lon") is None:
                continue
            street, bike = snapper.snap(e["lat"], e["lon"])
            out.append({"lat": e["lat"], "lon": e["lon"], "level": level,
                        "side": "right" if e.get("right_level", 0) >= level else "left",
                        "cls": e.get("cls", "unknown"), "gap_m": e.get("gap_m"), "ttc_s": e.get("ttc_seconds"),
                        "hour": local_hour(e.get("timestamp")), "street": street or "Other streets",
                        "bike_lane": bool(bike), "test_ride": bool(e.get("demo")), "synthetic": False})
    return out


def synthetic(dirpath):
    d = Path(dirpath)
    if not (d / "events.jsonl").exists():
        subprocess.run([sys.executable, str(HERE / "synth_events.py"), "--out", str(d)], check=True)
    events = [{"lat": e["lat"], "lon": e["lon"], "level": max(e["left_level"], e["right_level"]),
               "side": "right" if e["right_level"] else "left", "cls": e["cls"], "gap_m": e["gap_m"],
               "ttc_s": e["ttc_seconds"], "hour": local_hour(e["timestamp"]), "street": e["street"],
               "bike_lane": e["bike_lane"], "test_ride": False, "synthetic": True}
              for e in read_jsonl(d / "events.jsonl")]
    rides = [{"street": r["street"], "bike_lane": r["bike_lane"], "km": r["km"], "km_bike": r["km_bike"],
              "hour": local_hour(r["points"][0][2]), "synthetic": True,
              "coords": [[round(p[1], 5), round(p[0], 5)] for p in r["points"]]}
             for r in read_jsonl(d / "rides.jsonl")]
    return events, rides


def summary(events, rides):
    """Close passes per 100 km, by street, hour, vehicle and bike lane; for one source."""
    km = sum(r["km"] for r in rides) or 1e-9
    km_bike = sum(r["km_bike"] for r in rides)
    per_street = defaultdict(lambda: {"passes": 0, "km": 0.0})
    for r in rides:
        per_street[r["street"]]["km"] += r["km"]
    for e in events:
        per_street[e["street"]]["passes"] += 1
    streets = sorted(({"street": s, "passes": v["passes"], "km": round(v["km"], 1),
                       "per_100km": round(100 * v["passes"] / v["km"], 1)}
                      for s, v in per_street.items() if v["km"] >= 10),
                     key=lambda x: -x["per_100km"])
    bike = sum(1 for e in events if e["bike_lane"])
    return {
        "passes": len(events), "km": round(km, 1), "per_100km": round(100 * len(events) / km, 1),
        "imminent": sum(1 for e in events if e["level"] >= 3),
        "bike_lane_per_100km": round(100 * bike / km_bike, 1) if km_bike else None,
        "no_bike_lane_per_100km": round(100 * (len(events) - bike) / (km - km_bike), 1) if km > km_bike else None,
        "by_hour": [sum(1 for e in events if e["hour"] == h) for h in range(24)],
        "by_class": {c: sum(1 for e in events if e["cls"] == c) for c in sorted({e["cls"] for e in events})},
        "streets": streets,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--real", default="data/real")
    ap.add_argument("--synthetic", default="data/synthetic")
    ap.add_argument("--out", default="web/data")
    a = ap.parse_args()
    sys.path.insert(0, str(HERE))
    from synth_events import fetch_streets
    snapper = Snapper(fetch_streets())

    r = Path(a.real)
    ev_real = real_events(sorted(glob.glob(str(r / "events*.jsonl"))), snapper)
    rides_real = real_rides(sorted(glob.glob(str(r / "gps-*.jsonl")) + glob.glob(str(r / "ride-*.jsonl"))), snapper)
    ev_syn, rides_syn = synthetic(a.synthetic)

    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    events = ev_real + ev_syn
    rides = rides_real + rides_syn
    fc = lambda feats: {"type": "FeatureCollection", "features": feats}
    (out / "events.geojson").write_text(json.dumps(fc([
        {"type": "Feature", "geometry": {"type": "Point", "coordinates": [round(e["lon"], 5), round(e["lat"], 5)]},
         "properties": {k: v for k, v in e.items() if k not in ("lat", "lon")}} for e in events]),
        separators=(",", ":")))
    (out / "rides.geojson").write_text(json.dumps(fc([
        {"type": "Feature", "geometry": {"type": "LineString", "coordinates": p["coords"]},
         "properties": {k: (round(v, 3) if isinstance(v, float) else v) for k, v in p.items() if k != "coords"}}
        for p in rides]), separators=(",", ":")))
    built = {"generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
             "real": summary(ev_real, rides_real), "synthetic": summary(ev_syn, rides_syn),
             "all": summary(events, rides)}
    (out / "summary.json").write_text(json.dumps(built, indent=1))
    assert all(not e["synthetic"] for e in ev_real) and all(e["synthetic"] for e in ev_syn)
    print(f"real: {len(ev_real)} passes, {built['real']['km']} km | synthetic: {len(ev_syn)} passes, "
          f"{built['synthetic']['km']} km -> {out}/")


if __name__ == "__main__":
    main()
