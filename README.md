# Bike rear danger alert

Hack the Valley, School of Cities track.

A camera facing backward on a bicycle watches for vehicles coming up from behind. When one is
dangerously close, the matching handlebar vibrates. Near misses are logged, so they can be
mapped by ward next to Toronto's cyclist collision data.

## Folders

| Folder | What is in it | Owner |
|---|---|---|
| `ml/` | Vehicle detection, tracking and danger logic in Python, with tests. See `ml/README.md`. | Arshiya |
| `ios/DangerLogic/` | The same danger logic in Swift, with tests. | iOS app |
| `ios/models/` | Core ML vehicle detector (pretrained YOLO11 nano, not yet fine tuned). | iOS app |
| `api/` | Receives near miss events, joins them to wards, serves stats. Not started. | API |

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
- Swift danger logic: never compiled or run. Run the tests in Xcode first.
- Not yet tested on footage from a bike. Thresholds are starting guesses.
- No Toronto data downloaded yet.

## Data sources (the track brief asks for a link to every source we use)

| Source | Use | Status |
|---|---|---|
| Toronto Police, Cyclist KSI collisions: https://data.tps.ca/datasets/TorontoPS::cyclist-ksi/about | Where cyclists were seriously hurt, 2006 to 2023 | Not downloaded. Check it has coordinates. |
| Toronto Open Data, City Wards: https://open.toronto.ca/ | Ward boundaries | Not downloaded |
| OpenStreetMap, via Overpass Turbo: https://overpass-turbo.eu/ (credit OpenStreetMap contributors) | Bike lanes | Not downloaded |
| Statistics Canada, 2021 Census | People who bike to work | Not downloaded |
