# Bike rear danger alert

Hack the Valley, School of Cities track.

A camera facing backward on a bicycle watches for vehicles coming up from behind. When one is
dangerously close, the matching handlebar vibrates. Near misses are logged, so they can be
mapped by ward next to Toronto's cyclist collision data.

## Repo layout

| Folder | What is in it | Owner |
|---|---|---|
| `4sight/` | The iOS app (Xcode project, Rear/Front roles, `App/yolo11n.mlpackage`). | Jasper |
| `FourSightKit/` | Swift package: `Protocol`, `Perception`, `ThreatEngine` (incl. `Danger/`, the Swift port of `ml/danger.py`), `Links`. | Jasper |
| `firmware/` | ESP32 PlatformIO firmware for the grip motors and bar LEDs. | Arshiya |
| `docs/` | `CONTRACTS.md` (frozen formats) and `PLAN.md` (team plan). | all |
| `ml/` | Vehicle detection, tracking and danger logic in Python, with tests. See `ml/README.md`. | Arshiya |
| `api/` | Receives near miss events, joins them to wards, serves stats. Not started. | API |

Status: the rear pipeline (camera, YOLO, tracker, TTC/gap, ThreatEngine, BLE, peer link) builds and runs in the simulator; the Danger engine is wired in as a switchable second engine, untested on a bike.

## Proposed near miss record (to agree on before building the API)

Sent by the phone each time a warning starts. No rider name or id.

```
{
  "timestamp": "2026-10-17T14:03:22Z",
  "lat": 43.7731,
  "lon": -79.2574,
  "left_level": 0,
  "right_level": 3,
  "ttc_seconds": 1.6
}
```

Levels: 0 nothing, 1 gentle, 2 warning, 3 urgent. Times to collision are estimates from a single camera.

## Status

- Python danger logic: 25 tests and 6 tracker tests pass.
- Swift danger logic: compiles in `FourSightKit`; scenarios checked by `swift run Checks`.
- Not yet tested on footage from a bike. Thresholds are starting guesses.
- No Toronto data downloaded yet.

## Near-miss logging and the risk map

The rear phone appends one JSON line per alert episode (a track reaching level 2, and again if it escalates to 3) to `Documents/events.jsonl`: the proposed record above plus `speed`, `heading`, `gap_m`, `cls`, `engine`, `track_id`, `demo`. No rider name or id; `lat`/`lon` are `null` until the first GPS fix. The file is visible in the Files app and the rear screen has a "Share events" button (AirDrop it to a laptop).

Map it:

```
uv run --project tools tools/riskmap.py events.jsonl --route ride-*.jsonl [--ksi cyclist-ksi.csv] --out riskmap.html
uv run --project tools tools/riskmap.py --demo     # synthetic events along Bloor/College, labelled SYNTHETIC DATA
```

Layers: events coloured by level, a level-weighted heat layer, the ridden route, and the TPS cyclist KSI collisions if you pass the export (download it from the link in the table above, csv or geojson). It also prints the top 250 m grid cells by event count. School of Cities angle: with `lat`/`lon` per event the same file joins to City Wards and to the KSI points, so near misses recorded by riders can be compared ward by ward against where cyclists were actually hurt.

## Data sources (the track brief asks for a link to every source we use)

| Source | Use | Status |
|---|---|---|
| Toronto Police, Cyclist KSI collisions: https://data.tps.ca/datasets/TorontoPS::cyclist-ksi/about | Where cyclists were seriously hurt, 2006 to 2023 | Not downloaded. Check it has coordinates. |
| Toronto Open Data, City Wards: https://open.toronto.ca/ | Ward boundaries | Not downloaded |
| OpenStreetMap, via Overpass Turbo: https://overpass-turbo.eu/ (credit OpenStreetMap contributors) | Bike lanes | Not downloaded |
| Statistics Canada, 2021 Census | People who bike to work | Not downloaded |
