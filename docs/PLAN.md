# 4sight — master plan (36 h, first submission at hour 24)

Product name: 4sight (may change). Repo: github.com/mdadfarr/4sight. Contracts: `docs/CONTRACTS.md` (frozen).

## Team

| Who | Machine | Owns |
|---|---|---|
| **A — Jasper** | Mac + Xcode | The whole iOS core: Xcode project, `FourSightKit` (Protocol, Perception, ThreatEngine, Links), rear role UI, single-phone mode, integration, submission |
| **B — Arshiya** | Windows + RTX 3080 | Everything ML: `ml/` (Python detector, tracker, danger logic + tests, replay scripts), YOLO export to Core ML, the DangerEngine logic (Swift port lives in `FourSightKit/Sources/ThreatEngine/Danger/`), labels, metrics |
| **C** (Mac teammate, name TBC) | Mac + Xcode | Hardware build + firmware, runs the **frontend agent loop** (reviews/merges its PRs), demo video, pitch |
| **D** | — | Hardware build (wiring, box, mount, grips, LEDs), ride footage, demo video, pitch |

The front-phone UI is written by a Claude Code session using `.claude/skills/4sight-front/`, one screenshot-verified PR at a time. Humans approve PRs; nobody designs by hand.

## System

```
REAR iPhone 16 Pro Max (rack, facing back) — the brain, works alone
  camera 30 fps → Core ML yolo11n → Tracker → TTC/gap → ThreatEngine
  + CoreLocation (speed, heading, GPS log) + CoreMotion (heading wobble)
     ├─ BLE ──────► ESP32 (bar) ─► 4 coin motors (2/grip) + 2 amber LEDs (bar ends)
     └─ Wi-Fi P2P JSON 15 Hz ──► FRONT iPhone (same app, "Front" role): surround view + nav HUD
```
Single-phone mode = rear role with no front phone found: grips + LEDs only. Audio tones = reach.

## Decisions log

- **Two engines, switchable.** `ThreatEngine` (default): metric passing gap + inv TTC from GapEstimator/TTCEstimator, ISO-17387-style thresholds, alert-once, right-hook hold. `DangerEngine` (Arshiya's, `ThreatEngine/Danger/`): frame-fraction TTC from a line through 1/width, lateral check in vehicle widths, side by image thirds, 1 s hold. Both sit behind one `DetectionFilter` (min width 4 %, exclusion zones, large+unsure, size-jump reset). Switch with `-engine danger|threat` at launch or the Engine picker in RearView (`@AppStorage("engine")`); `-exclude x1,y1,x2,y2[;...]` sets the zones. Tomorrow's oncoming-car test runs both; we keep whichever fires correctly.

- **Front UI design is settled (2026-10-17)**: a slight follow camera over the rider showing the route ahead and the rear traffic, vehicles coloured by level, screen edges flashing the grip's beat. Source of truth is `docs/mock/front.html`; the brief in `.claude/skills/4sight-front/SKILL.md` summarises it. The vehicle rendering stays — a redesign that deleted it was not adopted.
- **Maps: Apple MapKit**, not Google. `MKDirections` with `.cycling` for the route, `MKLocalSearchCompleter` for search. Google's terms appear to bar DIY turn-by-turn from its Directions API (unverified, second-hand) and its sanctioned Navigation SDK targets drivers. Detections are placed relative to the rider from the camera, so GPS drift moves rider and traffic together. OpenStreetMap is for bike-lane and ward analysis, not routing.

- No DRV2605L. Bare motors on GPIO via transistor + flyback diode, PWM patterns in firmware. Two amber LEDs behave like a car blind-spot light (steady at level 1–2, flashing at 3).
- One native app, role toggle Rear/Front. Front UI is SwiftUI, agent-built.
- Nav HUD: real `MKDirections` cycling routes outdoors (iOS 26). Demo room: replay recorded ride video + its GPS log so surround view, alerts and nav move together. Hard-coded route is the fallback.
- Pedestrians: `person` class tracked and drawn; a threat only if closing and predicted to pass < 1 m (so a walking teammate in the demo room triggers; real pedestrians behind you don't).
- Night of day 0: code only. All on-device testing happens tomorrow morning, before the first submission; re-plan after.
- Metal box blocks BLE: antenna end out, or plastic lid. Range test is the first hardware test.
- Free Apple ID: one bundle ID, 7-day expiry, re-sign demo morning. Repo is public: no secrets ever.

## What's already written (night 0, by agents, untested on device)

- `docs/CONTRACTS.md` — frozen formats, UUIDs.
- `FourSightKit/` — Swift package; pure parts (`Protocol`, `ThreatEngine`, `Tracker`, `TTCEstimator`, `GapEstimator`) build and pass `swift test` on the Mac. iOS-only files (`CameraSource`, `FileSource`, `Detector`, `HapticsLink`, `PeerLink`) are behind `#if os(iOS)` and have never been compiled: expect to fix API nits in Xcode.
- `firmware/` — PlatformIO project, NimBLE peripheral, patterns, serial bench commands, wiring README.
- `.claude/skills/4sight-front/` — the frontend agent's brief, verification loop, PR rules.

## Manual checklist for Jasper (tonight, in this order)

1. `mv ~/Downloads/Xcode.app /Applications/ && sudo xcode-select -s /Applications/Xcode.app && xcodebuild -runFirstLaunch`
2. Ask the repo owner to add you, C and B as collaborators with push. Confirm with `gh api repos/mdadfarr/4sight --jq .permissions.push` → `true`.
3. In Xcode: File → New → Project → iOS App, name `4sight`, bundle id `com.<you>.foursight`, SwiftUI, save at `/Users/jasper/4sight/` (creates `4sight.xcodeproj` + `4sight/`). Then File → Add Package Dependencies → Add Local → `FourSightKit`, link all four library products to the app target.
4. Add `yolo11n.mlpackage` from B to the app target (Xcode compiles it; class name `yolo11n`).
5. Info.plist (target → Info): `NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription`, `NSMotionUsageDescription`, `NSBluetoothAlwaysUsageDescription`, `NSLocalNetworkUsageDescription`, `NSBonjourServices` = [`_foursight._tcp`]. Build settings: iOS 26 deployment target.
6. Replace `ContentView` with a role picker (Rear / Front). Rear = `RearView` you write; Front = `FrontRootView` the agent will add under `4sight/Front/` (stub it so the app compiles).
7. Build for Simulator once, commit, push. Tell C the frontend agent can start.
8. Plug in the 16 Pro Max, Developer Mode on, run once so signing works. Done for tonight.

## Jasper's build order (day 1)

| Step | Done when |
|---|---|
| 0. Rear mount is landscape. Tap Rear, look at the preview: if the road is upside down, rotate the phone 180° in the mount. Detection assumes landscape and this orientation. | Preview right way up |
| 1. Throwaway `BenchView`: live camera → Detector, print ms/inference, fps, thermal. Detection is capped at 10 fps for now (safety); raise only after this measurement | You know the number. < 25 ms → 640 at 30 fps; else 416, every other frame |
| 2. `RearPipeline`: CaptureSource → Detector → Tracker → TTC → Gap → ThreatEngine → FrameMessage | On the ride footage via `FileSource` in Simulator, an overtake shows inv_ttc > 0 ~3 s before the pass |
| 3. Wire `HapticsLink` + `PeerLink` + GPS/IMU into the pipeline; `RearView` with fps/thermal/links, `isIdleTimerDisabled`, dim | Grips buzz from a replayed overtake with no front phone connected |
| 4. GPS + video logger on the rear (for the demo-room replay) | A ride produces `ride.mov` + `ride.jsonl` |
| 5. Merge the agent's front PRs; two phones on the bike; stationary demo | Wheeled bike → level ≥ 2 → left grip within 1 s, glyph on front phone |
| 6. Demo video with C/D, README, Devpost | Submitted at hour 24 |
| 7. Validation ride, threshold tuning, demo-room replay synced with nav, metrics | Final at hour 36 |

## Cut line

- **Must by 24:** detection + tracking + ThreatEngine on device; BLE → grips + LEDs; front surround view over P2P; demo video; Devpost.
- **Should by 36:** real nav HUD; replayed-ride demo mode; right-hook alert; pedestrian handling; close-pass log; metrics in README.
- **Reach:** audio tones; Tiger Data upload.

## Hardware (C + D)

- Motors: GPIO 25, 26 (left pair), 32, 33 (right pair) → 1 kΩ → 2N2222 base (or logic-level N-MOSFET gate); motor between 3V3 and collector; 1N4148/1N4007 flyback across each motor, cathode to 3V3; 100 µF + 0.1 µF on 3V3. LEDs: GPIO 27 (left), 14 (right) → 220 Ω → amber LED → GND. USB power bank → ESP32. Never both grips at once (firmware enforces).
- Test order: serial commands → nRF Connect writes → range test through the box → on the bike from the power bank.
- Footage ride first thing in the morning: rear phone in the mount, 1x lens, 1080p30, 20–30 min downtown arterial + 5 min stationary with a wheeled bike and a walking person. Hand the file to B and A immediately.
- Demo video: rider with both phones live; second person films roadside; split screen of the front phone's screen recording and the outside shot; close-up of grip + LED; under 2 min.

## ML (B)

Export first, everything else after: `yolo export model=<their .pt> format=coreml nms=True imgsz=640 half=True` in WSL2; send the `.mlpackage` to A. Then `tools/replay.py` (JSONL of FrameMessage per frame from a video, using `model.track`), labels for validation, `tools/metrics.py`. Class names must stay within the six in CONTRACTS.md (or tell A the new ones before export).

---

# Base prompts

Paste as the first message in each person's agent. Replace `<...>`.

## Prompt A — Jasper (iOS core)

```
You are helping build 4sight, a 36-hour hackathon prototype. I own the entire iOS core. Read docs/CONTRACTS.md and docs/PLAN.md first; CONTRACTS.md is frozen.

System: a rear iPhone 16 Pro Max faces backwards on the bike rack, runs yolo11n (Core ML, NMS baked in), tracks vehicles and people, estimates time-to-contact (box area ∝ 1/Z², so d ln(area)/dt = 2/TTC) and sideways passing gap (gap ≈ (u_near − u0)/f × (Z + L), un-mirrored so negative x = rider's left), and a pure-Swift ThreatEngine decides levels 0–3. Outputs: FrameMessage JSON at 15 Hz over Network.framework peer-to-peer to a front iPhone running the same app in Front role, and ASCII BLE commands (L1..R3, X, H) to an ESP32 that drives grip motors and bar LEDs. The rear phone must work alone (no front phone) and must stay in the foreground.

Code lives in the local Swift package FourSightKit (targets Protocol, Perception, ThreatEngine, Links) plus the app target 4sight. ThreatEngine and the pure Perception maths already exist with passing `swift test`; iOS-only files (CameraSource, FileSource, Detector, HapticsLink, PeerLink) exist but have never compiled: fix them in place rather than rewriting. The front UI under 4sight/Front/ is owned by another agent; never edit it. Only I edit project.pbxproj; synchronized folders pick up new files.

Rules: Swift 6 toolchain, language mode 5, iOS 26, SwiftUI, no third-party packages, files under 300 lines, pure ThreatEngine stays free of iOS imports and keeps its tests green, no credentials, never send video over the link. Camera: back wide-angle 1x only, 1280×720 at 30 fps, stabilization off, focus locked far, intrinsics delivery on; on thermalState .serious drop to 416 input and detect every other frame. When you finish a step, tell me exactly what to run on the device to verify it.

Current step: <paste the row from "Jasper's build order" in docs/PLAN.md>.
```

## Prompt B — Arshiya: ML (Windows)

```
You are helping build 4sight, a 36-hour hackathon prototype that warns cyclists about vehicles approaching from behind using a rear-facing iPhone camera running YOLO. I own everything ML and the Python tooling in tools/. The iOS teammate consumes my outputs; docs/CONTRACTS.md defines the JSON and class names he expects and it is frozen.

Environment: Windows with an RTX 3080, WSL2 for anything that needs Linux (coremltools conversion only works there), Python 3.12 via uv. Deps: ultralytics, coremltools, opencv-python, numpy; nothing else unless I say.

Deliverables in order:
1. Core ML export of our YOLO model: `yolo export model=<ours.pt> format=coreml nms=True imgsz=640 half=True` in WSL2. Confirm the output class names are within {car, truck, bus, motorcycle, bicycle, person} or list the extra ones so the iOS side can map them. Send the .mlpackage to the iOS teammate today.
2. tools/replay.py: given a ride video, run the model with `model.track(persist=True, tracker="bytetrack.yaml")`, and per frame emit one FrameMessage JSON line exactly as in CONTRACTS.md. Maths: filtered ln(box area) slope / 2 = inv_ttc; freeze while the box touches the frame edge; gap = (u_near − u0)/f × (Z + L) with L = 4.5 car, 8 truck, 12 bus, 2.2 motorcycle, 1.8 bicycle, 0.5 person; Z = f·h/(v_bottom − v0) with camera height 1.0 m, fallback Z = f·1.8/w; the image is MIRRORED relative to the rider, so rider x = −gap. Use f and u0 from the iPhone intrinsics if provided, else f ≈ 0.9 × image width. Also write 3–5 short fixture cases (boxes in → inv_ttc/gap out) as JSON for the Swift unit tests.
3. tools/label.py: keyboard labeling of each pass in the ride (close under 1 m or not, right turn signal or not, timestamps). tools/metrics.py: close-pass recall, false alerts per km from the GPS log, median warning lead time. Targets: recall ≥ 90 %, false alerts < 1/km, lead time ≥ 2 s.
4. Turn-signal detection, heuristic first: amber-pixel ratio (HSV hue 15–40°, high S and V) in the lower-left and lower-right box quarters, "on" when it oscillates at 1–2 Hz over 1.5 s. The vehicle's RIGHT signal is in the LEFT half of its image box. Train a classifier only if the heuristic fails.

Rules: scripts under 300 lines, argparse CLIs, no notebooks in the repo, no cloud services, no credentials, don't change the JSON. Give me the exact uv commands for each script.

Current task: <step number>.
```

## Prompt C — hardware + firmware + frontend-loop operator (Mac)

```
You are helping build 4sight, a 36-hour hackathon prototype that warns cyclists about vehicles approaching from behind. I own the hardware build, the ESP32 firmware, and I operate the Claude Code session that builds the front-phone UI. Read docs/CONTRACTS.md (BLE section is my spec, frozen), firmware/README.md, and docs/PLAN.md "Hardware".

Hardware: ESP32-WROOM-32 dev board, four bare coin motors (two per grip) low-side switched from GPIO 25/26 (left) and 32/33 (right) through 2N2222s with 1 kΩ base resistors and 1N4148 flyback diodes, two amber LEDs on GPIO 27 (left) and 14 (right) through 220 Ω, 100 µF + 0.1 µF on 3V3, USB power bank. Metal enclosure: the board's antenna end must stick out or the lid must be plastic, otherwise BLE won't reach the phone.

Firmware already exists in firmware/ (PlatformIO, NimBLE-Arduino, non-blocking patterns, serial bench commands). My job is to build, upload, and test it in this order: motors from serial commands → BLE writes from the nRF Connect iOS app (connect to "4sight", write text L2, expect two left pulses + left LED) → range test through the box at 2 m → mounted on the bike from the power bank. Fix firmware bugs in place; never change the command format.

Frontend loop: in a separate Claude Code session in the repo, invoke the 4sight-front skill. It builds the front UI as small PRs with simulator screenshots. My job there is to read each PR's screenshots against the brief (Tesla passive surround view of what's behind the bike + Google Maps bike nav HUD on top), comment what's wrong, and merge when it looks right. Never more than 3 open PRs.

Also: film and cut the demo video (rider with both phones live, roadside shot, split screen with the front phone's screen recording, grip + LED close-up, under 2 minutes) and the pitch.

Rules: keep main.cpp under 300 lines, no extra libraries, don't commit secrets. Give me exact pio commands.

Current task: <paste from docs/PLAN.md>.
```

## Prompt D — Hardware build, footage, video, pitch

```
You are helping build 4sight, a 36-hour hackathon prototype that warns cyclists about vehicles approaching from behind. I'm on hardware assembly, the test-ride footage, the demo video and the pitch; I don't write app code. Read docs/PLAN.md "Hardware" and firmware/README.md for the wiring table.

My tasks: (1) wire four coin motors and two amber LEDs to the ESP32 per the wiring table, with transistors, flyback diodes and caps, strain-relieved leads, motors under the grip tape or inside foam grips, LEDs at the bar ends; (2) fit the ESP32 in the metal box with the antenna end exposed; (3) mount box and rear phone mount on the bike, power bank in the frame bag; (4) first thing in the morning record the test ride: rear phone in the rear mount, 1x lens, 1080p30, 20–30 min on a downtown Toronto arterial with parked cars and no bike lane, plus 5 min stationary with a teammate wheeling a bike toward the camera and one walking toward it; hand the files to the ML and iOS teammates immediately; (5) demo video under 2 minutes; (6) pitch: 9× injury risk on streets without protected lanes (2024 City of Toronto staff report), Bloor/Yonge/University lane removals, Garmin Varia does radar only, our camera adds right-hook warnings from turn signals, automatic close-pass logging, low cost; demo = stationary bike + wheeled bike + recorded footage.

When I ask for help, give me checklists, shopping lists (Canada Robotix, Creatron, Amazon.ca), and shot lists, not code.

Current task: <paste>.
```
