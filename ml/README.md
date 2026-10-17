# Bike danger: model and danger logic

## Files

| File | What it is | Who uses it |
|---|---|---|
| `../ios/models/yolo11n.mlpackage` | Pretrained vehicle detector as a Core ML model | Swift app |
| `../ios/DangerLogic/DangerEngine.swift` | Danger logic: time to collision, closeness, passing check, filters | Swift app |
| `../ios/DangerLogic/SimpleTracker.swift` | Gives each vehicle a persistent id between frames | Swift app |
| `../ios/DangerLogic/DangerEngineTests.swift` | 25 + 6 tests, to run before trusting the Swift | Swift app |
| `detect_video.py` | Runs the detector and tracker on a video, saves boxes per frame | Laptop |
| `danger.py`, `tracker.py` | The same logic in Python, the reference version | Laptop |
| `replay_danger.py` | Replays a clip through the danger logic, prints when alerts fire | Laptop |
| `test_danger.py`, `test_tracker.py` | Python tests (25 and 6, all passing) | Laptop |

## Laptop setup (any OS)

```
python -m venv .venv
source .venv/bin/activate          (Windows: .venv\Scripts\activate)
pip install ultralytics lapx "numpy<2.3"

python test_danger.py              (should say 25 of 25 passed)
python test_tracker.py             (should say 6 of 6 passed)

python detect_video.py my_clip.mp4
python replay_danger.py out/my_clip_boxes.csv
python replay_danger.py out/my_clip_boxes.csv --exclude 0.4,0,1,1     (ignore the right 60% of the picture)
```

`replay_danger.py` prints a line each time the alert level changes, for example
`t=0.40s left=URGENT right=URGENT ttc=1.59s`, and counts alert episodes.

## How the logic works

Filters, applied to every detection first:

1. Too small: boxes narrower than 4% of the frame are too far and too jittery. Ignored.
2. Exclusion zones: rectangles (fractions of the frame) where the bike's own parts appear. Ignored.
3. Large and unsure: a box at least half the frame wide with detector confidence under 0.5 is
   probably the bike's own parts. Ignored.
4. Sudden jump: if a box changes size by more than 1.6 times between two frames (a video cut
   or a tracker id swap), that vehicle's history is thrown away.

Then, for each tracked vehicle, over the last 0.5 s of box widths:

1. Growth rate: slope of a straight line through the widths (smooths jitter).
2. Time to collision: from a line through 1 / width. Exact for a vehicle closing at constant speed.
3. Under 2 s: level 3 (urgent). Under 3 s: level 2 (warning).
4. Box wider than 60% of the frame and growing even slowly: level 1 (gentle), for cars
   creeping in traffic. Parked cars (not growing) give nothing.
5. Passing check: how far the box sits off the picture's centre line, in units of its own
   width. Dead behind the bike is about 0. A car in the next lane is about 2. Over 1.0 means it
   will pass by, not hit the bike, so no alert. This still alerts on close passes (a car
   within about 1.8 m of the bike's centre line).
6. Side: image thirds. The camera faces backward, so image left is the rider's right. Middle
   third (directly behind) uses both handles.
7. An alert stays on for 1 s after the danger passes. A vehicle must be seen in at least
   5 frames inside the 0.5 s window, so the model must run at 10 fps or more.

## Wiring it into the Swift app

Per camera frame:

1. Run the Core ML model through Vision. Keep only car, motorcycle, bus, truck.
2. Turn each result's `boundingBox` (normalized, origin at the BOTTOM left) into a `Box` and
   call `SimpleTracker.update` to get ids.
3. Build `Detection(trackID:, centerX: box.centerX, width: box.width, centerY: ..., confidence: ...)`.
   `confidence` is the Vision observation's confidence. `centerY` only matters for exclusion
   zones, and since Vision's y points up, use `1 - boundingBox.midY`.
4. Create the engine with `frameWidth = 1.0` and `frameHeight = 1.0` and call
   `update(time:detections:)` every frame, even with no detections. `time` is the frame
   timestamp in seconds.
5. Send `output.left` and `output.right` (each 0 to 3) to the ESP32 over BLE as two bytes.
   The ESP32 decides the vibration per level, for example 1 = light pulse, 2 = medium, 3 = strong.

Set up once on the bike, with real footage:
- Exclusion zone around the rear wheel, mudguard, rack or anything of the bike's own that shows
  in the picture. Use `replay_danger.py --exclude` to find the numbers, then copy them into
  `DangerConfig.exclusionZones`.
- If left and right feel swapped, set `mirror = false`.

Things to check on a Mac first:
- Run the Swift tests (Cmd+U). They were written without a compiler, so a typo is possible.
- Does Vision return boxes that line up with the cars? Try both image crop and scale options.

## Results on clips so far (all Python, none from a bike)

| Clip | What it is | Alert episodes before filters | After |
|---|---|---|---|
| night_drive | camera on the side of a moving car | 4 | 2 (1 with the host car's body excluded; the rest are close passes) |
| city_street | fixed camera at a street corner | 1 | 1 |
| clip4k | dashcam compilation with cuts | 2 | 1 (a box that really doubles in 0.7 s) |

An episode is one stretch where an alert turns on and later off again.

These clips are not rear facing and not from a bike, so the alerts cannot be called right or wrong.

## What is NOT done or NOT verified

- Swift code has never been compiled or run. The Python versions are tested.
- Thresholds (3 s, 2 s, 60% closeness, 4% minimum, 1.0 lateral) are starting guesses. They need
  real footage from the bike mount, and a car is much faster than a bike.
- The detector is pretrained and not yet fine tuned for a bike's rear view.
- One camera cannot measure distance. Box size is a rough stand in, and a vehicle very close
  behind the bike may be cut off by the frame.
- The passing check assumes the camera looks straight back along the bike's direction.
