# Near-miss pipeline: app → server → Tiger Data → map

The contract between the app (front phone) and the server. Both sides build to this file;
change it only together.

## Flow

1. During a ride the **front phone** logs near misses (from the rear phone's frames) and its own
   GPS. The rider does nothing.
2. When the ride ends (Exit or arrival), if the rider left "Add my near misses to Toronto's
   public safety map" on (asked once, at setup), the app trims the first and last 200 m and
   POSTs the ride. No signal: it queues and retries.
3. The **server** (the only thing holding the database URL) validates, rate-limits and inserts
   into **Tiger Data** (TimescaleDB + PostGIS).
4. Tiger Data's **real-time continuous aggregates** keep close passes per 100 km by street
   segment, hour and lane type current, newest rows included.
5. The server publishes the result as public GeoJSON. The app's close-pass map and the
   website read it. Neither ever connects to the database.

No credentials in the app or the repo (it is public). No video, no rider identity.

## POST {BASE}/v1/rides

`Content-Type: application/json`, body at most 1 MB.

```json
{
  "install": "6f1c0a4e-…",          // random UUID made once per install; not tied to a person
  "app": "4sight/1.0",
  "demo": false,                    // true for demo mode, the scripted ride, the simulator
  "started": "2026-10-18T14:02:01Z",
  "ended": "2026-10-18T14:21:40Z",
  "points": [[1792332121.0, 43.78512, -79.18731, 4.1], …],   // [epoch s, lat, lon, speed m/s], ≤1 Hz, already trimmed
  "events": [
    {"t": 1792332277.4, "lat": 43.78601, "lon": -79.18902,
     "cls": "car", "level": 2, "side": "L", "gap_m": 0.8, "ttc_s": 2.4, "speed": 4.3}
  ]
}
```

- `cls`: car | truck | bus | motorcycle | bicycle | person. `level`: 2 threat, 3 imminent.
  `side`: L | R | - (which grip). `ttc_s` may be null. One event per vehicle per ride, at its
  worst level.
- Limits: ≤ 20 000 points, ≤ 500 events, lat 43.4–44.2, lon −80.0 to −78.8 (GTA), timestamps
  within the last 7 days and not in the future. At most 30 rides per install per hour.
- Responses: `200 {"ride_id": "…", "events": 1}`; `400` invalid; `413` too large; `429` rate
  limited. The app retries only on network errors and 5xx.

## GET {BASE}/v1/city-risk.geojson

Public, cacheable for 60 s. Query `?demo=1` includes demo rides (off by default).

```json
{"type": "FeatureCollection", "generated": "2026-10-18T14:23:05Z",
 "features": [
  {"type": "Feature",
   "geometry": {"type": "LineString", "coordinates": [[-79.18, 43.78], …]},
   "properties": {"street": "Ellesmere Road", "lane_type": "painted",
                  "km": 41.2, "passes": 17, "per_100km": 41.3,
                  "worst_hour": 17, "top_cls": "car", "synthetic_share": 0.8}},
  {"type": "Feature",
   "geometry": {"type": "Point", "coordinates": [-79.18902, 43.78601]},
   "properties": {"kind": "pass", "cls": "car", "level": 2, "gap_m": 0.8,
                  "hour": 14, "synthetic": false, "demo": false}}
 ]}
```

- `lane_type`: protected | painted | shared | none (from the City of Toronto Cycling Network
  when loaded, else OpenStreetMap). Segments with < 2 km ridden are omitted (too little exposure).
- Points: the most recent 500 passes.

## Database (Tiger Cloud)

- `segments(id, street, lane_type, geom geography(LineString))`, from OpenStreetMap
  (`4sight/Front/Streets.json`, roads) or the City Cycling Network.
- `ride_points` hypertable on `time`: ride_id, geom, speed, segment_id, km_from_prev, demo, synthetic.
- `near_misses` hypertable on `time`: ride_id, geom, cls, level, side, gap_m, ttc_s, speed,
  segment_id, demo, synthetic.
- Segment matching on insert: nearest segment within 25 m (PostGIS), else null.
- Continuous aggregates, `materialized_only = false` (real time):
  `segment_km_hourly` = time_bucket('1 hour'), segment_id, sum(km_from_prev);
  `segment_passes_hourly` = time_bucket('1 hour'), segment_id, count(*), max(level).
- Synthetic data from `tools/synth_events.py` loads into the same tables with `synthetic = true`.

## City of Toronto segments (hand-off between the City-data work and the backend)

Who: the City-data work produces this file; the backend loads it into `segments`. Until it
exists, the backend uses OpenStreetMap segments from `4sight/Front/Streets.json`, and nothing
else changes when the switch happens.

File: `data/city/segments.geojson` (committed; it is public City open data, no rider data).
A FeatureCollection of LineStrings in WGS84 (lon, lat), one feature per segment:

```json
{"type": "Feature",
 "geometry": {"type": "LineString", "coordinates": [[-79.1890, 43.7860], …]},
 "properties": {"segment_id": "city-12345",        // stable, from the City's own id
                "street": "Ellesmere Road",
                "lane_type": "protected" | "painted" | "shared" | "none",
                "ward": 25, "ward_name": "Scarborough-Rouge Park",
                "source": "City of Toronto Cycling Network",
                "city": { …the City's original fields, untouched… }}}
```

- `lane_type` from the City's infrastructure type: cycle track or multi-use trail → protected;
  bike lane or buffered bike lane → painted; sharrows, signed route or wayfinding → shared.
  Streets ridden that are not in the Cycling Network at all → `none` (from OpenStreetMap roads
  in the same area, `source: "OpenStreetMap"`).
- Wards from the City Wards boundaries (25-ward model), by the segment's midpoint.
- Regenerated by `tools/city_segments.py` (the City-data work owns it); the backend's loader
  is `tools/load_segments.py --source city`.
