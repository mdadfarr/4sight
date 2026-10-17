#!/usr/bin/env python3
"""Near-miss events (events.jsonl from the rear phone) -> riskmap.html of Toronto streets.

  uv run --project tools tools/riskmap.py events.jsonl [more.jsonl] [--route ride-*.jsonl] [--ksi ksi.csv]
  uv run --project tools tools/riskmap.py --demo        # synthetic events, labelled on the map
"""
import argparse
import glob
import json
import math
import random
from pathlib import Path

import folium
import pandas as pd
from folium.plugins import HeatMap

TORONTO = (43.6532, -79.3832)
CELL_M = 250
LAT_STEP = CELL_M / 111_320
LON_STEP = CELL_M / (111_320 * math.cos(math.radians(TORONTO[0])))
LEVEL_COLOUR = {2: "#ffb000", 3: "#ff3b30"}


def read_jsonl(paths):
    rows = []
    for pattern in paths:
        for p in sorted(glob.glob(str(pattern))) or [pattern]:
            with open(p) as f:
                for line in f:
                    line = line.strip()
                    if line:
                        rows.append(json.loads(line))
    return pd.DataFrame(rows)


def load_events(paths):
    df = read_jsonl(paths)
    if df.empty:
        raise SystemExit("no events found")
    df["level"] = df[["left_level", "right_level"]].max(axis=1)
    df = df[df["level"] >= 2]
    located = df.dropna(subset=["lat", "lon"])
    if len(located) < len(df):
        print(f"{len(df) - len(located)} events without a GPS fix are not drawn")
    return df, located


def haversine_km(lat1, lon1, lat2, lon2):
    p1, p2 = math.radians(lat1), math.radians(lat2)
    a = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(math.radians(lon2 - lon1) / 2) ** 2
    return 2 * 6371 * math.asin(math.sqrt(a))


def route_km(route):
    km = 0.0
    for i in range(1, len(route)):
        km += haversine_km(*route[i - 1], *route[i])
    return km


def load_ksi(path):
    """TPS cyclist KSI export: csv or geojson; lat/lon columns matched case-insensitively."""
    path = Path(path)
    if path.suffix.lower() in (".geojson", ".json"):
        feats = json.loads(path.read_text())["features"]
        pts = [f["geometry"]["coordinates"] for f in feats if f.get("geometry")]
        return [(lat, lon) for lon, lat, *_ in pts]
    df = pd.read_csv(path)
    cols = {c.lower(): c for c in df.columns}
    lat = next((cols[k] for k in cols if k in ("latitude", "lat", "lat_wgs84", "y")), None)
    lon = next((cols[k] for k in cols if k in ("longitude", "lon", "long", "long_wgs84", "x")), None)
    if not lat or not lon:
        raise SystemExit(f"no lat/lon columns in {path}: {list(df.columns)}")
    df = df[[lat, lon]].dropna()
    return list(zip(df[lat].astype(float), df[lon].astype(float)))


def cell_table(located):
    cells = located.assign(
        cell_lat=(located["lat"] // LAT_STEP) * LAT_STEP + LAT_STEP / 2,
        cell_lon=(located["lon"] // LON_STEP) * LON_STEP + LON_STEP / 2,
    )
    top = (cells.groupby(["cell_lat", "cell_lon"])
                .agg(events=("level", "size"), max_level=("level", "max"))
                .sort_values(["events", "max_level"], ascending=False)
                .head(10))
    return top


def render(df, located, routes, ksi, out, demo):
    # CARTO's free dark tiles now watermark "API KEY REQUIRED"; OSM's server answers
    # x-blocked under its tile policy. Esri's canvas tiles are open and need no key.
    m = folium.Map(location=TORONTO, zoom_start=13,
                   tiles="https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/"
                         "World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}",
                   attr="&copy; Esri, HERE, Garmin, &copy; OpenStreetMap contributors")
    if routes:
        fg = folium.FeatureGroup(name="Ridden route").add_to(m)
        for r in routes:
            folium.PolyLine(r, color="#9a9a9a", weight=3, opacity=0.7).add_to(fg)
    if ksi:
        fg = folium.FeatureGroup(name="TPS cyclist KSI collisions", show=True).add_to(m)
        for lat, lon in ksi:
            folium.CircleMarker((lat, lon), radius=2, color="#777", fill=True, fill_opacity=0.6, weight=0).add_to(fg)
    heat = folium.FeatureGroup(name="Near-miss heat (weighted by level)").add_to(m)
    HeatMap([[r.lat, r.lon, r.level] for r in located.itertuples()], radius=18, blur=15, min_opacity=0.3).add_to(heat)
    pts = folium.FeatureGroup(name="Near-miss events").add_to(m)
    for r in located.itertuples():
        ttc = f"{r.ttc_seconds:.1f} s" if pd.notna(r.ttc_seconds) else "–"
        popup = f"level {int(r.level)} · {r.cls} · gap {r.gap_m:.1f} m · ttc {ttc}<br>{r.timestamp}"
        folium.CircleMarker((r.lat, r.lon), radius=4 + 2 * (r.level - 2), color=LEVEL_COLOUR.get(int(r.level), "#fff"),
                            fill=True, fill_opacity=0.9, weight=1, popup=popup).add_to(pts)
    folium.LayerControl().add_to(m)
    if demo:
        m.get_root().html.add_child(folium.Element(
            '<div style="position:fixed;top:12px;left:60px;z-index:9999;background:#ff3b30;color:#fff;'
            'font:bold 14px sans-serif;padding:6px 10px;border-radius:6px">SYNTHETIC DATA</div>'))
    m.save(str(out))
    km = sum(route_km(r) for r in routes)
    print(f"total events: {len(df)}  (level 3: {int((df.level == 3).sum())})")
    if km:
        print(f"ridden: {km:.1f} km  ->  {len(df) / km:.1f} events per km")
    print(f"\ntop {CELL_M} m cells:")
    print(cell_table(located).to_string(float_format=lambda v: f"{v:.4f}"))
    print(f"\nwrote {out}")


def jitter_along(a, b, n, rng):
    """n points spread along the segment a->b with ~15 m of sideways noise."""
    out = []
    for _ in range(n):
        f = rng.random()
        out.append((a[0] + f * (b[0] - a[0]) + rng.gauss(0, 0.00012),
                    a[1] + f * (b[1] - a[1]) + rng.gauss(0, 0.00012)))
    return out


def make_demo(path):
    rng = random.Random(4)
    bloor = ((43.6553, -79.4597), (43.6648, -79.4113))    # Keele -> Bathurst
    college = ((43.6565, -79.4105), (43.6612, -79.3832))  # Bathurst -> Yonge
    pts = jitter_along(*bloor, 26, rng) + jitter_along(*college, 14, rng)
    with open(path, "w") as f:
        for i, (lat, lon) in enumerate(pts):
            level = 3 if rng.random() < 0.3 else 2
            left = rng.random() < 0.8
            rec = {"timestamp": f"2026-10-17T14:{i:02d}:00Z", "lat": round(lat, 6), "lon": round(lon, 6),
                   "speed": round(rng.uniform(3, 7), 2), "heading": round(rng.uniform(0, 360), 1),
                   "left_level": level if left else 0, "right_level": 0 if left else level,
                   "ttc_seconds": round(rng.uniform(0.8, 3.0), 2), "gap_m": round(rng.uniform(0.3, 1.0), 2),
                   "cls": rng.choice(["car", "car", "car", "truck", "bus"]), "engine": "threat",
                   "track_id": i, "demo": True}
            f.write(json.dumps(rec) + "\n")
    return path


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("events", nargs="*", help="events.jsonl file(s) from the rear phone")
    ap.add_argument("--route", nargs="*", default=[], help="ride-*.jsonl GPS logs to draw in grey")
    ap.add_argument("--ksi", help="TPS cyclist KSI export (csv or geojson), drawn as grey dots")
    ap.add_argument("--demo", action="store_true", help="generate demo-events.jsonl along Bloor/College and render it")
    ap.add_argument("--out", default="riskmap.html")
    a = ap.parse_args()
    out = Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    if a.demo:
        a.events = [make_demo(out.parent / "demo-events.jsonl")]
    if not a.events:
        ap.error("give events.jsonl file(s) or --demo")
    df, located = load_events(a.events)
    routes = []
    for p in a.route:
        r = read_jsonl([p])
        if not r.empty:
            routes.append(list(zip(r["lat"], r["lon"])))
    ksi = load_ksi(a.ksi) if a.ksi else []
    render(df, located, routes, ksi, out, a.demo)


if __name__ == "__main__":
    main()
