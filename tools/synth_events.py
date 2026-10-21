#!/usr/bin/env python3
"""Synthetic close-pass events and ride tracks on real Toronto arterials, so the city-scale
story on the website works before there are enough real rides. Every record carries
"synthetic": true and the site labels it as such.

  python3 tools/synth_events.py [--rides 800] [--seed 4] [--out data/synthetic]

Street geometry comes from OpenStreetMap (Overpass) once and is cached in
tools/cache/toronto_streets.json. Data © OpenStreetMap contributors, ODbL.

The model, so the numbers are explainable rather than random:
  - close passes per km: 0.30 with no bike lane, 0.10 with one (painted or separated)
  - x1.7 in the commute peaks (7–9, 16–19), x1.3 where the posted limit is 60, x0.7 at 40
  - vehicles: mostly cars; more trucks on Kingston/Lawrence/Dufferin, more buses on TTC routes
  - passing gap log-normal around 0.85 m (0.3–1.45), time-to-contact 0.6–3.5 s;
    level 3 (imminent) when the gap is under 0.6 m and contact is under 1.6 s away
"""
import argparse
import json
import math
import random
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
CACHE = HERE / "cache" / "toronto_streets.json"
UA = "4sight/0.1 (bike safety prototype)"
MIRRORS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]
STREETS = ("Bloor Street (West|East)|College Street|Dundas Street (West|East)|Queen Street (West|East)|"
           "King Street (West|East)|Spadina Avenue|Yonge Street|Danforth Avenue|Ellesmere Road|Military Trail|"
           "Morningside Avenue|Pan Am Drive|Bathurst Street|Dufferin Street|Gerrard Street East|Jarvis Street|"
           "Sherbourne Street|Lawrence Avenue East|Kingston Road")
QUERY = (f'[out:json][timeout:120];way[highway~"^(primary|secondary|tertiary|unclassified)$"]'
         f'[name~"^({STREETS})$"](43.635,-79.47,43.80,-79.17);out geom tags;')
BIKE_VALUES = {"lane", "track", "separate", "shared_busway"}

# How often riders use each street in the synthetic month (downtown commuting corridors
# heavier, the Scarborough campus streets lighter but present: that is where we test).
WEIGHT = {"Bloor Street West": 9, "Bloor Street East": 4, "College Street": 7, "Dundas Street West": 6,
          "Dundas Street East": 3, "Queen Street West": 7, "Queen Street East": 4, "King Street West": 6,
          "King Street East": 3, "Spadina Avenue": 5, "Yonge Street": 7, "Danforth Avenue": 6,
          "Bathurst Street": 4, "Dufferin Street": 3, "Gerrard Street East": 3, "Jarvis Street": 2,
          "Sherbourne Street": 3, "Ellesmere Road": 3, "Military Trail": 3, "Morningside Avenue": 2,
          "Pan Am Drive": 1, "Lawrence Avenue East": 2, "Kingston Road": 2}
TRUCKY = {"Kingston Road", "Lawrence Avenue East", "Dufferin Street", "Ellesmere Road"}
TTC_BUS = {"Dufferin Street", "Bathurst Street", "Spadina Avenue", "Ellesmere Road", "Morningside Avenue",
           "Lawrence Avenue East", "Kingston Road", "Military Trail", "Jarvis Street", "Sherbourne Street"}


def fetch_streets():
    """Overpass once, compacted to [{name, bike, maxspeed, pts:[[lat,lon],...]}]; cached."""
    if CACHE.exists():
        return json.loads(CACHE.read_text())
    body = urllib.parse.urlencode({"data": QUERY}).encode()
    for attempt in range(6):
        try:
            req = urllib.request.Request(MIRRORS[attempt % 2], data=body, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=180) as r:
                raw = json.load(r)
            break
        except Exception as e:  # public Overpass servers are flaky: next mirror, back off
            print(f"overpass: {e}")
            time.sleep(5 * (attempt + 1))
    else:
        raise SystemExit("Overpass unreachable and no cache at " + str(CACHE))
    ways = []
    for el in raw["elements"]:
        t = el.get("tags", {})
        bike = any(t.get(k) in BIKE_VALUES for k in ("cycleway", "cycleway:both", "cycleway:left", "cycleway:right"))
        try:
            limit = int(t.get("maxspeed", "50").split()[0])
        except ValueError:
            limit = 50
        ways.append({"name": t["name"], "bike": bike, "maxspeed": limit,
                     "pts": [[round(g["lat"], 6), round(g["lon"], 6)] for g in el["geometry"]]})
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps(ways, separators=(",", ":")))
    return ways


def metres(a, b):
    """Equirectangular distance, metres; exact enough across a city."""
    k = math.cos(math.radians((a[0] + b[0]) / 2))
    return math.hypot((b[0] - a[0]) * 111_320, (b[1] - a[1]) * 111_320 * k)


def chains(ways):
    """Ways of one street joined end to end, so a ride can run along several of them."""
    by_end = {}
    for i, w in enumerate(ways):
        for end in (tuple(w["pts"][0]), tuple(w["pts"][-1])):
            by_end.setdefault((w["name"], end), []).append(i)
    return by_end


def ride_path(ways, by_end, rng, start, target_m):
    """Walks connected ways of the same street from `start` until about target_m long."""
    w = ways[start]
    pts = list(w["pts"]) if rng.random() < 0.5 else list(reversed(w["pts"]))
    segs = [(w["bike"], w["maxspeed"], len(pts))]
    used = {start}
    length = sum(metres(pts[i - 1], pts[i]) for i in range(1, len(pts)))
    while length < target_m:
        nxt = [j for j in by_end.get((w["name"], tuple(pts[-1])), []) if j not in used]
        if not nxt:
            break
        j = rng.choice(nxt)
        used.add(j)
        w2 = ways[j]
        more = w2["pts"] if tuple(w2["pts"][0]) == tuple(pts[-1]) else list(reversed(w2["pts"]))
        length += sum(metres(more[i - 1], more[i]) for i in range(1, len(more)))
        pts += more[1:]
        segs.append((w2["bike"], w2["maxspeed"], len(pts)))
    return pts, segs, length


def segment_at(segs, index):
    for bike, limit, upto in segs:
        if index < upto:
            return bike, limit
    return segs[-1][0], segs[-1][1]


def hour_weights():
    """Commute peaks, a lunchtime shoulder, almost nothing overnight."""
    w = [0.2] * 24
    for h, v in {6: 1, 7: 4, 8: 6, 9: 3, 10: 1.5, 11: 1.5, 12: 2.2, 13: 2, 14: 1.6, 15: 2,
                 16: 3.5, 17: 6, 18: 5, 19: 2.5, 20: 1.5, 21: 1, 22: 0.5}.items():
        w[h] = v
    return w


def generate(ways, rides=800, seed=4, days=28, end=None):
    rng = random.Random(seed)
    end = end or datetime(2026, 10, 17, 18, 0, tzinfo=timezone.utc)
    by_end = chains(ways)
    names = [n for n in WEIGHT if any(w["name"] == n for w in ways)]
    hours = hour_weights()
    out_rides, out_events, track_id = [], [], 1
    for r in range(rides):
        name = rng.choices(names, weights=[WEIGHT[n] for n in names])[0]
        start = rng.choice([i for i, w in enumerate(ways) if w["name"] == name])
        pts, segs, length = ride_path(ways, by_end, rng, start, rng.uniform(1200, 4500))
        if length < 300:
            continue
        hour = rng.choices(range(24), weights=hours)[0]
        day = end - timedelta(days=rng.randrange(days))
        # Toronto is UTC-4 in October; store UTC like the phone's ISO timestamps do.
        t0 = day.replace(hour=(hour + 4) % 24, minute=rng.randrange(60), second=0)
        v = rng.uniform(4.0, 6.2)
        times, acc = [], 0.0
        for i in range(len(pts)):
            if i:
                acc += metres(pts[i - 1], pts[i])
            times.append(t0 + timedelta(seconds=acc / v))
        rush = hour in (7, 8, 16, 17, 18)
        ride_bike = sum(1 for b, _, _ in segs if b) / len(segs)
        km_bike = sum(metres(pts[i - 1], pts[i]) for i in range(1, len(pts)) if segment_at(segs, i)[0]) / 1000
        out_rides.append({"id": f"s{r}", "street": name, "synthetic": True, "bike_lane": ride_bike >= 0.5,
                          "km": round(length / 1000, 3), "km_bike": round(km_bike, 3),
                          "points": [[p[0], p[1], t.strftime("%Y-%m-%dT%H:%M:%SZ")] for p, t in zip(pts, times)]})
        # Walk the path in 25 m steps; each step may hold a close pass.
        cum = [0.0]
        for i in range(1, len(pts)):
            cum.append(cum[-1] + metres(pts[i - 1], pts[i]))
        s = 0.0
        while s < length:
            i = max(k for k in range(len(cum)) if cum[k] <= s)
            bike, limit = segment_at(segs, i)
            rate = (0.10 if bike else 0.30) * (1.7 if rush else 1.0)
            rate *= 1.3 if limit >= 60 else 0.7 if limit <= 40 else 1.0
            if rng.random() < rate * 0.025:  # per 25 m
                j = min(i + 1, len(pts) - 1)
                f = (s - cum[i]) / max(cum[j] - cum[i], 1e-6)
                lat = pts[i][0] + (pts[j][0] - pts[i][0]) * f
                lon = pts[i][1] + (pts[j][1] - pts[i][1]) * f
                cls = rng.choices(["car", "truck", "bus", "motorcycle"],
                                  weights=[78, 12 if name in TRUCKY else 5, 9 if name in TTC_BUS else 2, 4])[0]
                gap = min(max(rng.lognormvariate(math.log(0.85), 0.32), 0.3), 1.45)
                ttc = rng.uniform(0.6, 3.5)
                level = 3 if gap < 0.6 and ttc < 1.6 else 2
                right = rng.random() < 0.06  # a right hook, the rare one
                out_events.append({
                    "timestamp": (times[i] + timedelta(seconds=(s - cum[i]) / v)).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "lat": round(lat, 6), "lon": round(lon, 6), "speed": round(v, 2), "heading": -1,
                    "left_level": 0 if right else level, "right_level": level if right else 0,
                    "ttc_seconds": round(ttc, 2), "gap_m": round(gap, 2), "cls": cls, "engine": "threat",
                    "track_id": track_id, "demo": False, "synthetic": True,
                    "street": name, "bike_lane": bike})
                track_id += 1
            s += 25
    return out_rides, out_events


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rides", type=int, default=800)
    ap.add_argument("--seed", type=int, default=4)
    ap.add_argument("--out", default="data/synthetic")
    a = ap.parse_args()
    rides, events = generate(fetch_streets(), a.rides, a.seed)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    with open(out / "events.jsonl", "w") as f:
        f.writelines(json.dumps(e) + "\n" for e in events)
    with open(out / "rides.jsonl", "w") as f:
        f.writelines(json.dumps(r) + "\n" for r in rides)
    km = sum(r["km"] for r in rides)
    print(f"{len(rides)} rides, {km:.0f} km, {len(events)} close passes -> {out}/")
    assert all(e["synthetic"] for e in events) and all(r["synthetic"] for r in rides)


if __name__ == "__main__":
    main()
