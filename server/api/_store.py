"""Everything the two endpoints share: validation of an app upload, the insert, and the
public GeoJSON. tools/load_synthetic.py inserts through `insert_ride` too, so modelled
data takes exactly the path real rides do. Parameterised SQL only.
Contract: docs/DATA_PIPELINE.md."""
import hashlib
import json
import math
import os
import uuid
from datetime import datetime, timezone

import psycopg

MAX_BODY = 1_000_000
MAX_POINTS, MAX_EVENTS = 20_000, 500
RIDES_PER_HOUR = 30
LAT, LON = (43.4, 44.2), (-80.0, -78.8)
CLASSES = {"car", "truck", "bus", "motorcycle", "bicycle", "person"}
SIDES = {"L", "R", "-"}
# A gap faster than this between 1 Hz fixes is lost signal, not riding: no km counted.
MAX_SPEED = 20.0


class Invalid(Exception):
    """400 with this message, or 413 when `too_large`."""

    def __init__(self, msg, too_large=False):
        super().__init__(msg)
        self.too_large = too_large


def connect():
    return psycopg.connect(os.environ["DATABASE_URL"], connect_timeout=10)


def _num(v, lo, hi, what):
    if isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) or not lo <= v <= hi:
        raise Invalid(f"{what} out of range")
    return float(v)


def _time(v, now, what):
    t = _num(v, 0, 1e11, what)
    if not now - 7 * 86400 <= t <= now + 300:   # 5 min of phone clock skew
        raise Invalid(f"{what} not within the last 7 days")
    return t


def _iso(v, what):
    try:
        return datetime.fromisoformat(str(v).replace("Z", "+00:00")).timestamp()
    except ValueError:
        raise Invalid(f"{what} is not an ISO 8601 time")


def validate(body: bytes, now: float | None = None) -> dict:
    """The upload as plain values, or Invalid. Mirrors RideUpload in FourSightKit."""
    now = now if now is not None else datetime.now(timezone.utc).timestamp()
    if len(body) > MAX_BODY:
        raise Invalid("body over 1 MB", too_large=True)
    try:
        r = json.loads(body)
    except ValueError:
        raise Invalid("not JSON")
    if not isinstance(r, dict):
        raise Invalid("not an object")
    try:
        install = str(uuid.UUID(str(r.get("install"))))
    except ValueError:
        raise Invalid("install must be a UUID")
    if not isinstance(r.get("demo"), bool):
        raise Invalid("demo must be true or false")
    points, events = r.get("points"), r.get("events")
    if not isinstance(points, list) or not isinstance(events, list) or not points:
        raise Invalid("points and events must be lists, points not empty")
    if len(points) > MAX_POINTS or len(events) > MAX_EVENTS:
        raise Invalid("too many points or events", too_large=True)
    pts = []
    for p in points:
        if not isinstance(p, list) or len(p) != 4:
            raise Invalid("each point is [t, lat, lon, speed]")
        pts.append((_time(p[0], now, "point time"), _num(p[1], *LAT, "lat"), _num(p[2], *LON, "lon"),
                    _num(p[3], 0, 60, "speed")))
    evs = []
    for e in events:
        if not isinstance(e, dict) or e.get("cls") not in CLASSES or e.get("side") not in SIDES \
                or e.get("level") not in (2, 3) or isinstance(e.get("level"), bool):
            raise Invalid("event cls, side or level invalid")
        ttc = e.get("ttc_s")
        evs.append({"t": _time(e.get("t"), now, "event time"), "lat": _num(e.get("lat"), *LAT, "lat"),
                    "lon": _num(e.get("lon"), *LON, "lon"), "cls": e["cls"], "level": e["level"],
                    "side": e["side"], "gap_m": _num(e.get("gap_m"), 0, 50, "gap_m"),
                    "ttc_s": None if ttc is None else _num(ttc, 0, 1000, "ttc_s"),
                    "speed": _num(e.get("speed"), 0, 60, "speed")})
    return {"install": install, "demo": r["demo"], "started": _iso(r.get("started"), "started"),
            "ended": _iso(r.get("ended"), "ended"), "points": sorted(pts), "events": evs}


def install_key(install: str) -> str:
    return hashlib.sha256(install.encode()).hexdigest()


def rate_limited(conn, install: str) -> bool:
    n = conn.execute("SELECT count(*) FROM rides WHERE install = %s AND received > now() - interval '1 hour'",
                     (install_key(install),)).fetchone()[0]
    return n >= RIDES_PER_HOUR


def _metres(a, b):
    """Haversine metres between (t, lat, lon, …) points."""
    p = math.pi / 180
    h = math.sin((b[1] - a[1]) * p / 2) ** 2 + \
        math.cos(a[1] * p) * math.cos(b[1] * p) * math.sin((b[2] - a[2]) * p / 2) ** 2
    return 2 * 6_371_000 * math.asin(min(1, math.sqrt(h)))


def _ts(t):
    return datetime.fromtimestamp(t, timezone.utc)


def insert_ride(conn, ride: dict, synthetic: bool = False) -> str:
    """One ride in one transaction; segments are matched by the table triggers."""
    with conn.transaction():
        ride_id = conn.execute(
            "INSERT INTO rides (install, started, ended, demo, synthetic) VALUES (%s, %s, %s, %s, %s) RETURNING id",
            (install_key(ride["install"]), _ts(ride["started"]), _ts(ride["ended"]), ride["demo"], synthetic),
        ).fetchone()[0]
        with conn.cursor() as cur:
            with cur.copy("COPY ride_points (time, ride_id, geom, speed, km_from_prev, demo, synthetic) FROM STDIN") as cp:
                prev = None
                for p in ride["points"]:
                    d = _metres(prev, p) if prev else 0.0
                    km = d / 1000 if prev and d <= MAX_SPEED * max(p[0] - prev[0], 1) else 0.0
                    cp.write_row((_ts(p[0]), ride_id, f"SRID=4326;POINT({p[2]} {p[1]})", p[3], km,
                                  ride["demo"], synthetic))
                    prev = p
            cur.executemany(
                "INSERT INTO near_misses (time, ride_id, geom, cls, level, side, gap_m, ttc_s, speed, demo, synthetic) "
                "VALUES (%s, %s, ST_GeogFromText(%s), %s, %s, %s, %s, %s, %s, %s, %s)",
                [(_ts(e["t"]), ride_id, f"SRID=4326;POINT({e['lon']} {e['lat']})", e["cls"], e["level"], e["side"],
                  e["gap_m"], e["ttc_s"], e["speed"], ride["demo"], synthetic) for e in ride["events"]])
    return str(ride_id)


SEGMENTS_SQL = """
WITH km AS (
    SELECT segment_id, sum(km) AS km, coalesce(sum(km) FILTER (WHERE synthetic), 0) AS syn_km
    FROM segment_km_hourly WHERE segment_id IS NOT NULL AND (NOT demo OR %(demo)s) GROUP BY 1),
passes AS (
    SELECT segment_id, sum(passes)::int AS passes
    FROM segment_passes_hourly WHERE segment_id IS NOT NULL AND (NOT demo OR %(demo)s) GROUP BY 1),
hours AS (
    SELECT DISTINCT ON (segment_id) segment_id, h FROM (
        SELECT segment_id, extract(hour FROM bucket AT TIME ZONE 'America/Toronto')::int AS h, sum(passes) AS n
        FROM segment_passes_hourly WHERE segment_id IS NOT NULL AND (NOT demo OR %(demo)s) GROUP BY 1, 2) x
    ORDER BY segment_id, n DESC, h),
cls AS (
    SELECT DISTINCT ON (segment_id) segment_id, cls FROM (
        SELECT segment_id, cls, count(*) AS n FROM near_misses
        WHERE segment_id IS NOT NULL AND (NOT demo OR %(demo)s) GROUP BY 1, 2) x
    ORDER BY segment_id, n DESC, cls)
SELECT ST_AsGeoJSON(s.geom, 6), s.street, s.lane_type, km.km, coalesce(p.passes, 0),
       hours.h, cls.cls, km.syn_km / km.km
FROM segments s JOIN km ON km.segment_id = s.id
LEFT JOIN passes p ON p.segment_id = s.id
LEFT JOIN hours ON hours.segment_id = s.id
LEFT JOIN cls ON cls.segment_id = s.id
WHERE km.km >= 2
"""

POINTS_SQL = """
SELECT ST_X(n.geom::geometry), ST_Y(n.geom::geometry), n.cls, n.level, n.gap_m,
       extract(hour FROM n.time AT TIME ZONE 'America/Toronto')::int, n.synthetic, n.demo,
       s.street, s.lane_type
FROM near_misses n LEFT JOIN segments s ON s.id = n.segment_id
WHERE NOT n.demo OR %(demo)s
ORDER BY n.time DESC LIMIT 500
"""


def city_risk(conn, demo: bool = False) -> dict:
    """The public layer: segments with ≥ 2 km ridden, and the newest 500 passes."""
    q = {"demo": demo}
    features = []
    for geom, street, lane, km, passes, hour, cls, syn in conn.execute(SEGMENTS_SQL, q):
        features.append({"type": "Feature", "geometry": json.loads(geom), "properties": {
            "street": street, "lane_type": lane, "km": round(km, 1), "passes": int(passes),
            "per_100km": round(100 * passes / km, 1), "worst_hour": hour, "top_cls": cls,
            "synthetic_share": round(syn, 2)}})
    for lon, lat, cls, level, gap, hour, syn, dem, street, lane in conn.execute(POINTS_SQL, q):
        # street and lane_type are extra to the contract's point properties (additive).
        features.append({"type": "Feature", "geometry": {"type": "Point", "coordinates": [round(lon, 6), round(lat, 6)]},
                         "properties": {"kind": "pass", "cls": cls, "level": level,
                                        "gap_m": None if gap is None else round(gap, 2), "hour": hour,
                                        "synthetic": syn, "demo": dem, "street": street, "lane_type": lane}})
    return {"type": "FeatureCollection",
            "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "features": features}
