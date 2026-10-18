#!/usr/bin/env python3
"""Prints a demo ride as the app would POST it: ~300 m along Ellesmere Road by the Pan Am
Centre, ending now, with one close pass by a car. demo: true, so the public map leaves it
out unless asked (?demo=1).

  python3 tools/demo_ride.py | curl -sS -X POST "$BASE/v1/rides" -H 'Content-Type: application/json' --data @-
"""
import json
import math
import time
import uuid

# Ellesmere Road centre line, OpenStreetMap (tools/cache/toronto_streets.json), lat/lon.
PATH = [(43.786577, -79.188271), (43.786537, -79.188431), (43.786438, -79.188848), (43.785740, -79.191643)]
SPEED = 4.5  # m/s


def metres(a, b):
    k = math.cos(math.radians((a[0] + b[0]) / 2))
    return math.hypot((b[0] - a[0]) * 111_320, (b[1] - a[1]) * 111_320 * k)


def main():
    pts = []
    for a, b in zip(PATH, PATH[1:]):
        steps = max(1, round(metres(a, b) / SPEED))
        pts += [(a[0] + (b[0] - a[0]) * i / steps, a[1] + (b[1] - a[1]) * i / steps) for i in range(steps)]
    pts.append(PATH[-1])
    t0 = time.time() - len(pts)
    near = min(range(len(pts)), key=lambda i: abs(pts[i][1] - -79.1890))   # the pass by 43.786, -79.189
    lat, lon = pts[near]
    ride = {"install": str(uuid.uuid4()), "app": "4sight/demo", "demo": True,
            "started": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t0)),
            "ended": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t0 + len(pts))),
            "points": [[round(t0 + i, 1), round(la, 6), round(lo, 6), SPEED] for i, (la, lo) in enumerate(pts)],
            "events": [{"t": round(t0 + near + 0.4, 1), "lat": round(lat, 6), "lon": round(lon, 6), "cls": "car",
                        "level": 2, "side": "L", "gap_m": 0.8, "ttc_s": 2.4, "speed": SPEED}]}
    print(json.dumps(ride))


if __name__ == "__main__":
    main()
